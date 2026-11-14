import SwiftUI

/// Shared tab strip using macos-components' compact tab surfaces and MacVue's
/// roving keyboard selection. Content stays owned by the caller's session.
struct TahoeTabs<Item: Identifiable, Label: View>: View {
    var items: [Item]
    @Binding var selection: Item.ID?
    var close: (Item.ID) -> Void
    var add: () -> Void
    var reorder: ((Item.ID, Item.ID) -> Void)? = nil
    @ViewBuilder var label: (Item) -> Label
    @FocusState private var focus: Item.ID?
    @Environment(\.layoutDirection) private var direction
    @State private var dragged: Item.ID?
    @State private var dragToken = UUID()
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(items) { item in
                        HStack(spacing: 5) {
                            Button { selection = item.id } label: { label(item).frame(minWidth: 65, maxWidth: 160) }
                                .buttonStyle(TahoePressStyle()).focused($focus, equals: item.id)
                                .accessibilityAddTraits(selection == item.id ? [.isSelected] : [])
                                .onKeyPress { key in
                                    let delta: Int
                                    switch key.key { case .leftArrow: delta = direction == .rightToLeft ? 1 : -1; case .rightArrow: delta = direction == .rightToLeft ? -1 : 1; default: return .ignored }
                                    if let next = TahoeMenuNavigation.next(from: items.firstIndex(where: { $0.id == item.id }), direction: delta, enabled: items.map { _ in true }) {
                                        selection = items[next].id; focus = items[next].id
                                    }
                                    return .handled
                                }
                            Button { close(item.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).frame(width: 16, height: 18) }
                                .buttonStyle(TahoePressStyle()).accessibilityLabel("Close tab")
                        }.padding(.horizontal, 10).frame(height: 29)
                            .background { RoundedRectangle(cornerRadius: 7).fill(TahoeDesign.content).opacity(selection == item.id ? 1 : 0) }
                            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(selection == item.id ? 0.08 : 0), lineWidth: 0.5) }
                            .shadow(color: .black.opacity(selection == item.id ? 0.05 : 0), radius: 1, y: 1)
                            .modifier(TahoeTabReordering(id: item.id, origin: $dragged, token: $dragToken, reorder: reorder))
                            .id(item.id)
                    }
                    TahoeToolbarButton(symbol: "plus", label: "New tab", action: add)
                }.padding(.horizontal, 8).padding(.vertical, 4).tahoeGlassGroup()
            }.onChange(of: selection) { _, id in if let id { proxy.scrollTo(id) } }
        }.background(TahoeDesign.window)
    }
}

struct TahoeTabReordering<ID: Hashable>: ViewModifier {
    let id: ID
    @Binding var origin: ID?
    @Binding var token: UUID
    var reorder: ((ID, ID) -> Void)?
    var beginTransfer: ((String) -> Void)? = nil
    private let type = "com.aault.tahoe.browser-tab"
    @ViewBuilder func body(content: Content) -> some View {
        if let reorder {
            content.onDrag {
                origin = id; token = UUID()
                beginTransfer?(token.uuidString)
                let data = Data(token.uuidString.utf8)
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .ownProcess) { completion in completion(data, nil); return nil }
                return provider
            }.onDrop(of: [type], isTargeted: nil) { providers in
                guard let provider = providers.first, origin != nil else { return false }
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    guard let data, let value = String(data: data, encoding: .utf8) else { return }
                    DispatchQueue.main.async {
                        guard value == token.uuidString, let origin else { return }
                        reorder(origin, id); self.origin = nil
                    }
                }
                return true
            }
        } else { content }
    }
}

/// macos-components/MacVue help control; content is presented in an anchored
/// floating surface, with a native accessibility description and Escape dismiss.
struct TahoeHelpButton: View {
    var title: String
    var message: String
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: {
            Text(TahoeStrings.ui("?")).font(.system(size: 14, weight: .medium)).frame(width: 24, height: 24)
                .background(TahoeDesign.content, in: Circle())
                .overlay { Circle().strokeBorder(.primary.opacity(0.16), lineWidth: 0.75) }
                .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.5)
        }.buttonStyle(TahoePressStyle()).accessibilityLabel(title)
            .popover(isPresented: $open, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 13, weight: .semibold)); Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
                    .padding(16).frame(width: 280).presentationCompactAdaptation(.popover)
                    .onKeyPress(.escape) { open = false; return .handled }
            }
    }
}

private struct TahoeTooltip: ViewModifier {
    @Environment(\.tahoeWindowVisible) private var windowVisible
    var title: String
    @State private var visible = false
    @State private var pending: Task<Void, Never>?
    func body(content: Content) -> some View {
        content.onHover { over in
            pending?.cancel(); visible = false
            if over {
                pending = Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(500)); guard !Task.isCancelled else { return }; visible = true } catch { }
                }
            }
        }.overlay(alignment: .bottom) {
            if visible {
                Text(title).font(.system(size: 11)).fixedSize().padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.16), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2).offset(y: 28).allowsHitTesting(false).accessibilityHidden(true)
            }
        }.onChange(of: windowVisible) { _, visible in if !visible { pending?.cancel(); self.visible = false } }
            .onDisappear { pending?.cancel() }.accessibilityHint(title)
    }
}

extension View { func tahoeTooltip(_ title: String) -> some View { modifier(TahoeTooltip(title: title)) } }

/// Equal-width iPad Safari tabs. The entire label (including whitespace)
/// selects its retained WKWebView; only the explicit close glyph closes it.
struct TahoeBrowserTabs: View {
    @ObservedObject var session: TahoeBrowserSession
    @ObservedObject private var preferences = TahoePreferences.shared
    @State private var dragged: UUID?
    @State private var hovered: UUID?
    @State private var token = UUID()
    @FocusState private var focus: UUID?
    @Environment(\.layoutDirection) private var direction
    @State private var frames: [UUID: CGRect] = [:]
    private var windowID: UUID? { TahoeWorkspace.shared.browsers.first(where: { $0.value === session })?.key }
    private var tabHeight: CGFloat { TahoeDesign.tabHeight }
    private var rowHeight: CGFloat { 40 }
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(session.stripTabs) { tab in
                            let selected = session.selectedID == tab.id
                            HStack(spacing: 2) {
                                Button { session.close(tab.id) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .regular))
                                        .frame(width: 44, height: rowHeight)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(TahoePressStyle())
                                .foregroundStyle(.primary.opacity(0.72))
                                .accessibilityLabel("Close \(tab.title)")
                                Button { session.selectedID = tab.id } label: {
                                    TahoeTabLabel(tab: tab)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(TahoePressStyle())
                                .focused($focus, equals: tab.id)
                                .foregroundStyle(Color.primary.opacity(selected ? 1 : 0.78))
                                .accessibilityIdentifier("browser-tab-\(tab.id)")
                                .accessibilityAddTraits(selected ? [.isSelected] : [])
                                .onKeyPress { key in
                                    guard key.key == .leftArrow || key.key == .rightArrow,
                                        let next = TahoeMenuNavigation.next(
                                            from: session.stripTabs.firstIndex(where: { $0.id == tab.id }),
                                            direction: (key.key == .leftArrow ? -1 : 1) * (direction == .rightToLeft ? -1 : 1),
                                            enabled: session.stripTabs.map { _ in true }
                                        ) else { return .ignored }
                                    session.selectedID = session.stripTabs[next].id
                                    focus = session.selectedID
                                    return .handled
                                }
                            }
                            .padding(.horizontal, 5)
                            .frame(width: max(142, (geometry.size.width - 16 - CGFloat(max(0, session.stripTabs.count - 1)) * 2) / CGFloat(max(1, session.stripTabs.count))), height: rowHeight)
                            .contentShape(Capsule())
                            .tahoeBrowserTab(selected: selected)
                            .overlay {
                                Capsule().fill(.white.opacity(hovered == tab.id && !selected ? 0.055 : 0))
                                    .allowsHitTesting(false)
                            }
                            .background { GeometryReader { cell in Color.clear.preference(key: TahoeBrowserTabFrames.self, value: [tab.id: cell.frame(in: .global)]) } }
                            .onDrop(of: ["com.aault.tahoe.browser-tab"], delegate: TahoeBrowserTabBarDrop(windowID: windowID ?? UUID(), before: tab.id))
                            .contextMenu {
                                Button(TahoeStrings.ui("Move Tab to New Window")) { TahoeWorkspace.shared.detachBrowserTab(tab.id, session: session) }
                                Button(tab.pinned ? "Unpin Tab / Allow Sleep" : "Pin Tab / Keep Awake") { tab.pinned.toggle(); session.changed?() }
                                Button(TahoeStrings.ui("Find on Page")) { tab.activePage.findOnPage() }
                                Button("Move to Tab Group…") {
                                    TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Tab Group", message: "Enter a group name, or leave it empty to ungroup this tab.", primary: "Save", initialText: tab.group ?? "", accept: { value in
                                        if let value { tab.group = value.isEmpty ? nil : String(value.prefix(60)); session.selectGroup(tab.group); session.changed?() }
                                    })
                                }
                            }
                            .onHover { over in if over { hovered = tab.id } else if hovered == tab.id { hovered = nil } }
                            .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 1)
                    .padding(.bottom, 3)
                }
                .onChange(of: session.selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .frame(height: tabHeight)
        .onPreferenceChange(TahoeBrowserTabFrames.self) { frames = $0 }
        .background { TahoeNativeTabDrag(session: session, frames: frames) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-chrome-tab-strip")
        .tahoeGlassGroup()
        .background { TahoeWindowChrome(active: true, browser: true) }
    }
}

