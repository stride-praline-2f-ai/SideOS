import SwiftUI

/// Public keyboard geometry, converted into the app window's coordinate space.
/// Desktop geometry stays fixed; individual sheets avoid the keyboard instead.
@MainActor final class TahoeKeyboard: ObservableObject {
    static let shared = TahoeKeyboard()
    @Published private(set) var frame = CGRect.null
    private var observers: [NSObjectProtocol] = []
    init() {
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let hidden = note.name == UIResponder.keyboardWillHideNotification
                let screenFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .null
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if hidden || screenFrame.isNull { self.frame = .null }
                    else if let window = Self.window { self.frame = window.convert(screenFrame, from: window.screen.coordinateSpace) }
                    else { self.frame = screenFrame }
                }
            })
        }
    }
    static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
    }
    static func dismiss() {
        window?.endEditing(true)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    func availableHeight(in rect: CGRect) -> CGFloat {
        let overlap = rect.intersection(frame)
        guard !overlap.isNull, overlap.width > rect.width * 0.5 else { return rect.height }
        return max(0, min(rect.height, frame.minY - rect.minY - 12))
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}
