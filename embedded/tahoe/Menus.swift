import SwiftUI

/// Shared desktop menus: macos-components' row metrics, disabled/check states,
/// popup/navigation patterns; native keyboard, pointer and touch presentation.
struct TahoeMenuEntry: Identifiable {
    var title: String
    var shortcut = ""
    var symbol = ""
    var enabled = true
    var checked = false
    var key: String?
    var separator = false
    var destructive = false
    var children: [TahoeMenuEntry] = []
    var action: () -> Void = {}
    var id: String { key ?? title }
    static func line(_ number: Int) -> Self { Self(title: "separator-\(number)", separator: true) }
    static func normalized(_ entries: [Self], path: String = "menu") -> [Self] {
        entries.enumerated().map { index, item in
            var item = item; item.key = item.key ?? "\(path).\(index)"
            item.children = normalized(item.children, path: item.key!); return item
        }
    }
}

struct TahoeMenuRequest: Identifiable {
    let id = UUID()
    var anchor: CGRect
    var entries: [TahoeMenuEntry]
}

@MainActor final class TahoeMenuCoordinator: ObservableObject {
    static let shared = TahoeMenuCoordinator()
    @Published private(set) var session = TahoeMenuSession<TahoeMenuKind>()
    private var contextual: TahoeMenuRequest?
    private(set) var lastAnchor: CGRect?
    var request: TahoeMenuRequest? { session.contextID == contextual?.id ? contextual : nil }
    var bar: TahoeMenuKind? { session.bar }
    func selectBar(_ kind: TahoeMenuKind?) {
        guard session.bar != kind || session.contextID != nil else { return }
        contextual = nil
        session.select(kind)
    }
    func show(anchor: CGRect, entries: [TahoeMenuEntry]) {
        lastAnchor = anchor
        TahoeWorkspace.shared.overlay = nil
        let request = TahoeMenuRequest(anchor: anchor, entries: entries)
        contextual = request
        session.showContext(request.id)
    }
    func dismiss() {
        guard session.isOpen else { return }
        contextual = nil
        session.dismiss()
    }
}

struct TahoePopupButton<Label: View>: View {
    let entries: [TahoeMenuEntry]
    var glass = false
    @ViewBuilder var label: () -> Label
    @State private var anchor = CGRect.zero
    var body: some View {
        Button { TahoeMenuCoordinator.shared.show(anchor: anchor, entries: entries) } label: { label() }
            .buttonStyle(TahoePressStyle(surface: glass, radius: 100)).accessibilityHint("Opens menu")
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear { anchor = geometry.frame(in: .named("tahoe-desktop")) }
                        .onChange(of: geometry.frame(in: .named("tahoe-desktop"))) { _, frame in anchor = frame }
                }
            }
    }
}

private struct TahoeMenuRowKey: Hashable { var depth: Int; var id: String }
private struct TahoeMenuRowFrames: PreferenceKey {
    static var defaultValue: [TahoeMenuRowKey: CGRect] = [:]
    static func reduce(value: inout [TahoeMenuRowKey: CGRect], nextValue: () -> [TahoeMenuRowKey: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

final class TahoeResponderBox { weak var value: UIResponder? }
extension UIResponder {
    @objc func tahoeCaptureResponder(_ sender: Any?) { (sender as? TahoeResponderBox)?.value = self }
}

struct TahoeMenuSurface: View {
    var anchor: CGRect
    var entries: [TahoeMenuEntry]
    var canvas: CGSize
    // Omitted for ordinary contextual/toolbar menus, which use panelGlass.
    var transparency: Double? = nil
    var dismiss: () -> Void
    var switchMenu: ((Int) -> Void)?
    var revision = 0
    @State private var path: [String] = []
    @State private var committed = false
    @State private var selected: [Int: String] = [:]
    @State private var frames: [TahoeMenuRowKey: CGRect] = [:]
    @State private var query = ""
    @State private var queryDate = Date.distantPast
    @State private var responder = TahoeResponderBox()
    @State private var restoredFocus = false
    @State private var sourceWindow: UUID?
    @State private var appeared = false
    @State private var previousPointer: CGPoint?
    @State private var pointer: CGPoint?
    @State private var pendingHighlight: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var preferences = TahoePreferences.shared
    private var rowHeight: CGFloat { 44 }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).onTapGesture { close() }.accessibilityLabel("Dismiss menu").accessibilityAddTraits(.isButton)
            ForEach(0...path.count, id: \.self) { depth in
                let rows = items(at: depth)
                let rect = rectangle(at: depth)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rows) { entry in row(entry, depth: depth).id(entry.id) }
                        }.padding(5)
                    }.scrollBounceBehavior(.basedOnSize)
                        .onChange(of: selected[depth]) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }.frame(width: rect.width, height: rect.height)
                    .modifier(TahoeGlass(radius: 7, transparency: transparency))
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.14), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
                    // Animate only the first entrance. Heading switches and
                    // dismissal never leave an outgoing dropdown on screen.
                    .scaleEffect(reduceMotion || appeared ? 1 : 0.985, anchor: .topLeading)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: appeared)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }.onPreferenceChange(TahoeMenuRowFrames.self) { frames = $0 }
            // Replace the contents in place. No outgoing menu is retained by
            // an implicit animation, and the original editor keeps its focus.
            .transaction { $0.animation = nil }
            .focusable().focused($focused).focusEffectDisabled()
            .onAppear {
                sourceWindow = TahoeWorkspace.shared.state.activeID
                UIApplication.shared.sendAction(#selector(UIResponder.tahoeCaptureResponder(_:)), to: nil, from: responder, for: nil)
                focused = true
                appeared = true
            }
            .onChange(of: revision) { _, _ in
                path = []; selected = [:]; frames = [:]; query = ""
                queryDate = .distantPast; committed = false
            }
            .onDisappear { pendingHighlight?.cancel(); restoreResponder() }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): previousPointer = pointer; pointer = point
                case .ended: previousPointer = nil; pointer = nil
                }
            }
            .onKeyPress { key in handle(key) }
            .accessibilityElement(children: .contain).accessibilityLabel("Menu").accessibilityAddTraits(.isModal)
    }
    private func row(_ entry: TahoeMenuEntry, depth: Int) -> some View {
        Group {
            if entry.separator { Divider().padding(.horizontal, 8).padding(.vertical, 5) }
            else {
                let highlighted = selected[depth] == entry.id
                Button { activate(entry, depth: depth) } label: {
                    HStack(spacing: 8) {
                        Group {
                            if entry.checked || !entry.symbol.isEmpty { Image(systemName: entry.checked ? "checkmark" : entry.symbol).font(.system(size: 11, weight: .semibold)) }
                            else { Color.clear }
                        }.frame(width: 14, height: 14)
                        Text(entry.title).lineLimit(1)
                        Spacer(minLength: 8)
                        if !entry.children.isEmpty { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
                        else { Text(entry.shortcut).font(.system(size: 12)).opacity(0.65) }
                    }.font(.callout).padding(.horizontal, 8).frame(height: rowHeight).contentShape(Rectangle())
                        .foregroundStyle(!entry.enabled ? Color.secondary.opacity(0.5) : highlighted ? TahoeDesign.accentForeground : entry.destructive ? .red : .primary)
                        .background(highlighted && entry.enabled ? TahoeDesign.accent : .clear, in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(TahoePressStyle(scale: 1, pointerEffect: false)).disabled(!entry.enabled)
                    .accessibilityLabel(entry.title).accessibilityHint(entry.shortcut)
                    .onHover { over in
                        if over && entry.enabled {
                            pendingHighlight?.cancel()
                            if path.count > depth, path[depth] != entry.id, let previousPointer, let pointer,
                               TahoeMenuPointerIntent.towardSubmenu(from: previousPointer, to: pointer, submenu: rectangle(at: depth + 1)) {
                                pendingHighlight = Task { @MainActor in
                                    do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                                    highlight(entry, depth: depth, expand: true)
                                }
                            } else { highlight(entry, depth: depth, expand: true) }
                        }
                        else if over {
                            selected[depth] = nil
                            path = Array(path.prefix(depth))
                        }
                    }
                    .accessibilityValue(entry.checked ? "Selected" : "")
                    .background {
                        GeometryReader { geometry in Color.clear.preference(key: TahoeMenuRowFrames.self, value: [TahoeMenuRowKey(depth: depth, id: entry.id): geometry.frame(in: .named("tahoe-desktop"))]) }
                    }
            }
        }
    }
    private func items(at depth: Int) -> [TahoeMenuEntry] {
        var current = TahoeMenuEntry.normalized(entries)
        for id in path.prefix(depth) { current = current.first(where: { $0.id == id })?.children ?? [] }
        return current
    }
    private func rectangle(at depth: Int) -> CGRect {
        let rows = items(at: depth)
        let height = rows.reduce(CGFloat(10)) { $0 + ($1.separator ? 11 : rowHeight) }
        let parent = depth == 0 ? anchor : frames[TahoeMenuRowKey(depth: depth - 1, id: path[depth - 1])] ?? rectangle(at: depth - 1)
        return TahoePopupGeometry.frame(anchor: parent, size: CGSize(width: 280, height: height), canvas: canvas, submenu: depth > 0)
    }
    private func highlight(_ entry: TahoeMenuEntry, depth: Int, expand: Bool) {
        selected[depth] = entry.id
        if path.count > depth { path = Array(path.prefix(depth)) }
        selected = selected.filter { $0.key <= depth }
        if expand && !entry.children.isEmpty { path.append(entry.id) }
    }
    private func activate(_ entry: TahoeMenuEntry, depth: Int) {
        guard entry.enabled, !entry.separator else { return }
        if !entry.children.isEmpty {
            highlight(entry, depth: depth, expand: true)
            move(1, depth: depth + 1)
        } else {
            guard !committed else { return }; committed = true
            close()
            // Menu focus must not redirect Cut/Copy/Paste away from the editor.
            DispatchQueue.main.async { entry.action() }
        }
    }
    private func move(_ delta: Int, depth: Int) {
        let rows = items(at: depth)
        if let index = TahoeMenuNavigation.next(from: rows.firstIndex(where: { $0.id == selected[depth] }), direction: delta, enabled: rows.map { $0.enabled && !$0.separator }) {
            highlight(rows[index], depth: depth, expand: false)
        }
    }
    private func restoreResponder() {
        guard !restoredFocus else { return }
        restoredFocus = true
        guard TahoeWorkspace.shared.state.activeID == sourceWindow else { return }
        responder.value?.becomeFirstResponder()
    }
    private func close() { focused = false; dismiss(); restoreResponder() }
    private func handle(_ key: KeyPress) -> KeyPress.Result {
        let depth = path.count
        let rows = items(at: depth)
        switch key.key {
        case .escape: close()
        case .downArrow: move(1, depth: depth)
        case .upArrow: move(-1, depth: depth)
        case .home: selected[depth] = rows.first(where: { $0.enabled && !$0.separator })?.id
        case .end: selected[depth] = rows.last(where: { $0.enabled && !$0.separator })?.id
        case .return, .space:
            if let entry = rows.first(where: { $0.id == selected[depth] }) { activate(entry, depth: depth) }
        case .rightArrow:
            if let entry = rows.first(where: { $0.id == selected[depth] }), !entry.children.isEmpty { activate(entry, depth: depth) }
            else if depth == 0 { switchMenu?(1) }
        case .leftArrow:
            if !path.isEmpty { path.removeLast() }
            else { switchMenu?(-1) }
        case .tab: close()
        default:
            guard !key.modifiers.contains(.command), !key.modifiers.contains(.control), key.characters.count == 1 else { return .ignored }
            if Date().timeIntervalSince(queryDate) > 0.8 { query = "" }
            queryDate = Date(); query += key.characters
            let index = rows.firstIndex(where: { $0.id == selected[depth] })
            if let match = TahoeMenuNavigation.match(query, titles: rows.map(\.title), enabled: rows.map { $0.enabled && !$0.separator }, after: index)
                ?? TahoeMenuNavigation.match(key.characters, titles: rows.map(\.title), enabled: rows.map { $0.enabled && !$0.separator }, after: index) {
                highlight(rows[match], depth: depth, expand: false)
            }
        }
        return .handled
    }
}

struct TahoeToolbarActions: View {
    let commands: [TahoeMenuEntry]
    var body: some View {
        GeometryReader { geometry in
            let count = TahoeToolbarOverflow.visibleCount(widths: commands.map { _ in 28 }, available: geometry.size.width)
            HStack(spacing: 6) {
                ForEach(Array(commands.prefix(count))) { command in
                    if command.children.isEmpty {
                        TahoeToolbarButton(symbol: command.symbol, label: command.title, action: command.action).disabled(!command.enabled)
                    } else {
                        TahoePopupButton(entries: command.children, glass: true) { Image(systemName: command.symbol).frame(width: 28, height: 28) }.disabled(!command.enabled).accessibilityLabel(command.title)
                    }
                }
                if count < commands.count {
                    TahoePopupButton(entries: Array(commands.dropFirst(count)), glass: true) { Image(systemName: "chevron.right.2").frame(width: 28, height: 28) }
                        .accessibilityLabel("More toolbar actions")
                }
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }.frame(height: 28)
    }
}

