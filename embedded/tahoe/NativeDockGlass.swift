import SwiftUI

/// Native optical recipes, applied to the fitted Dock panel after layout.
/// Icons retain their own input feedback; the backdrop is not a giant button.
struct TahoeNativeDockGlass: ViewModifier {
    @ObservedObject private var preferences = TahoePreferences.shared
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let style = preferences.value.nativeDockGlassStyle
        content.background {
            if opaque || style == "solid" {
                shape.fill(preferences.value.appearance == "oled" ? Color.black : scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
            } else if #available(iOS 26.0, *) {
                Color.clear.glassEffect(style == "regular" ? .regular : .clear, in: shape)
            } else {
                shape.fill(.regularMaterial)
            }
        }
    }
}
