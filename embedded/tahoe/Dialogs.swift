import SwiftUI

@MainActor final class TahoeModalRegistry: ObservableObject {
    static let shared = TahoeModalRegistry()
    @Published private(set) var owners: Set<UUID> = []
    func set(_ owner: UUID, blocking: Bool) { if blocking { owners.insert(owner) } else { owners.remove(owner) } }
}

/// macos-components Sheet/Alert and macos_ui's parent-window modal pattern.
/// Presentation stays inside its owning desktop window rather than taking over
/// the iPad. System permissions, sharing and file pickers remain native.
struct TahoeDialog: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var symbol = "info.circle"
    var primary = "OK"
    var cancel: String? = "Cancel"
    var destructive = false
    var initialText: String?
    var validate: (String) -> Bool = { _ in true }
    var accept: (String?) -> Void
    var reject: () -> Void = {}
}

@MainActor final class TahoeDialogCoordinator: ObservableObject {
    static let shared = TahoeDialogCoordinator()
    @Published private var presented: TahoeDialog?
    private var pending: [TahoeDialog] = []
    var dialog: TahoeDialog? {
        get { presented }
        set {
            if let newValue {
                if presented != nil { pending.append(newValue) }
                else { presented = newValue }
            } else {
                presented = nil
                if !pending.isEmpty { presented = pending.removeFirst() }
            }
        }
    }
}

struct TahoeDialogView: View {
    let dialog: TahoeDialog
    let dismiss: () -> Void
    @ObservedObject private var keyboard = TahoeKeyboard.shared
    @State private var text = ""
    @State private var completed = false
    @FocusState private var focused: Bool
    @Environment(\.tahoeWindowVisible) private var windowVisible
    @Environment(\.tahoeWindowActive) private var windowActive
    var body: some View {
        GeometryReader { geometry in
            let height = keyboard.availableHeight(in: geometry.frame(in: .global))
            ZStack(alignment: .top) {
                Color.black.opacity(0.14).contentShape(Rectangle()).accessibilityHidden(true)
                ScrollView {
                    card.frame(maxWidth: .infinity).frame(minHeight: height)
                }.scrollBounceBehavior(.basedOnSize).frame(height: height)
            }

        }.onChange(of: windowVisible) { _, visible in if !visible { if focused { TahoeKeyboard.dismiss() }; focused = false } }
            .onChange(of: windowActive) { _, active in if !active { focused = false } }
            .onAppear {
                if windowActive && windowVisible { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                text = dialog.initialText ?? ""; focused = dialog.initialText != nil && windowActive && windowVisible
            }
    }
    private var card: some View {
            VStack(spacing: 14) {
                Image(systemName: dialog.symbol).font(.system(size: 34)).foregroundStyle(dialog.destructive ? Color.orange : TahoeDesign.accent)
                Text(dialog.title).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center)
                ScrollView {
                    Text(dialog.message).font(.callout).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).textSelection(.enabled)
                }.frame(maxHeight: 240).scrollBounceBehavior(.basedOnSize)
                if dialog.message.count > 350 {
                    Button(TahoeStrings.ui("Copy Details")) { UIPasteboard.general.string = dialog.message }
                        .buttonStyle(TahoeControlStyle())
                }
                if dialog.initialText != nil {
                    TextField(TahoeStrings.ui("Name"), text: $text).textFieldStyle(.plain).focused($focused).tahoeField(focused: focused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { accept() }
                }
                HStack(spacing: 8) {
                    if let cancel = dialog.cancel {
                        Button(cancel) { reject() }.buttonStyle(TahoeControlStyle()).keyboardShortcut(.cancelAction)
                    }
                    Button(dialog.primary) { accept() }
                        .buttonStyle(TahoeControlStyle(variant: dialog.destructive ? .destructive : .accent))
                        .disabled(!dialog.validate(text)).keyboardShortcut(.defaultAction)
                }.tahoeGlassGroup().padding(.top, 2)
            }.padding(22).frame(maxWidth: 360).background(TahoeDesign.window, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10).padding(16)
                .accessibilityElement(children: .contain).accessibilityLabel(dialog.title)
            .task(id: focused) {
                guard focused else { return }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard focused, windowVisible, windowActive else { return }
                let responder = TahoeResponderBox()
                UIApplication.shared.sendAction(#selector(UIResponder.tahoeCaptureResponder(_:)), to: nil, from: responder, for: nil)
                if let field = responder.value as? UITextField, field.text == text { field.selectAll(nil) }
            }
    }
    private func accept() { guard !completed, dialog.validate(text) else { return }; completed = true; focused = false; dismiss(); dialog.accept(dialog.initialText == nil ? nil : text) }
    private func reject() { guard !completed else { return }; completed = true; focused = false; dismiss(); dialog.reject() }
}

extension View {
    func tahoeDialog(_ dialog: Binding<TahoeDialog?>) -> some View {
        modifier(TahoeDialogHost(dialog: dialog))
    }
}
private struct TahoeDialogHost: ViewModifier {
    @Binding var dialog: TahoeDialog?
    @State private var owner = UUID()
    @Environment(\.tahoeWindowActive) private var active
    @Environment(\.tahoeWindowVisible) private var visible
    func body(content: Content) -> some View {
        ZStack {
            content.accessibilityHidden(dialog != nil)
            if let dialog { TahoeDialogView(dialog: dialog, dismiss: { self.dialog = nil }).id(dialog.id) }
        }.onChange(of: dialog != nil && active && visible, initial: true) { _, blocks in TahoeModalRegistry.shared.set(owner, blocking: blocks) }
            .onDisappear { TahoeModalRegistry.shared.set(owner, blocking: false) }
    }
}

enum TahoeShare {
    @MainActor static func present(_ items: [Any], window: UIWindow? = nil, sourceRect: CGRect? = nil) {
        guard let window = window ?? TahoeKeyboard.window, var controller = window.rootViewController else { return }
        while let presented = controller.presentedViewController { controller = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = controller.view
        sheet.popoverPresentationController?.sourceRect = sourceRect.map { controller.view.convert($0, from: window) } ?? CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
        controller.present(sheet, animated: true)
    }
}

