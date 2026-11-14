import SwiftUI

private struct TahoeOLEDKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tahoeOLED: Bool {
        get { self[TahoeOLEDKey.self] }
        set { self[TahoeOLEDKey.self] = newValue }
    }
}

/// Resolve from the environment so switching Dark → OLED updates existing
/// surfaces immediately, even though both modes use the same dark color scheme.
enum TahoeSurface: ShapeStyle, View {
    case window, content, group

    func resolve(in environment: EnvironmentValues) -> Color {
        if environment.tahoeOLED { return .black }
        let dark = environment.colorScheme == .dark
        switch self {
        case .window: return Color(white: dark ? 0.15 : 0.965)
        case .content: return dark ? Color(white: 0.14) : .white
        case .group: return dark ? Color(white: 0.18) : .white
        }
    }

    var body: some View { Rectangle().fill(self) }
}
