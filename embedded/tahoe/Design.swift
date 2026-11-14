import SwiftUI

enum TahoeDesign {
    // Paired 1280px screenshots of the standard 1376pt 13-inch M4 canvas.
    @MainActor static var menuBarHeight: CGFloat { TahoeDisplayMetrics.shared.current.menuHeight }
    static let menuFontSize: CGFloat = 14
    // MacVue regular-control tokens, expressed in points. See Notices/.
    static let controlHeight: CGFloat = 24
    static let controlRadius: CGFloat = 6
    static let windowRadius: CGFloat = 16
    static let accent = Color.accentColor
    // Compact document chrome; browser controls share its unified toolbar.
    @MainActor static var titleHeight: CGFloat { TahoePreferences.shared.comfortableControlsEnabled ? 48 : 44 }
    @MainActor static var trafficInset: CGFloat { 148 }
    @MainActor static var navigationHeight: CGFloat { TahoePreferences.shared.value.compactDesktop ? 48 : 53 }
    @MainActor static var tabHeight: CGFloat { TahoePreferences.shared.comfortableControlsEnabled ? 53 : 44 }
    @MainActor static var dockMaximum: CGFloat {
        let value = CGFloat(TahoePreferences.shared.value.dockSize)
        return TahoePreferences.shared.value.compactDesktop ? max(24, value * 0.84) : value
    }
    @MainActor static var accentForeground: Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(TahoePreferences.shared.value.accentColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ value: CGFloat) -> Double { let value = Double(value); return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? .black : .white
    }
    static let window = TahoeSurface.window
    static let content = TahoeSurface.content
    static let group = TahoeSurface.group
}

/// Window glass belongs to the toolbar, not underneath an entire live app.
/// A neutral tint keeps the wallpaper from turning every title bar blue.
struct TahoeWindowChrome: View {
    @ObservedObject private var preferences = TahoePreferences.shared
    var active: Bool
    var browser = false
    private var clarity: Double { TahoeNumeric.value(preferences.value.panelGlass, in: 0...1) }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque
    private var neutral: Color { preferences.value.appearance == "oled" ? .black : scheme == .dark ? Color(white: 0.16) : Color(white: 0.96) }
    var body: some View {
        Group {
            if browser {
                // Fixed opaque backing: not a glass surface and never a
                // webpage-sampling layer. The seven dark shades are independent
                // of existing browser control material and scrolling.
                preferences.value.appearance == "oled" ? Color.black : scheme == .dark ? preferences.value.browserBarShade.color : neutral
            } else if opaque || clarity == 0 {
                neutral
            } else if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(neutral.opacity((1 - clarity) * (active ? 0.5 : 0.7))), in: Rectangle())
            } else {
                Rectangle().fill(.regularMaterial)
                    .overlay(neutral.opacity((1 - clarity) * (active ? 0.5 : 0.7)))
            }
        }
        // The browser's navigation and tabs form one uninterrupted glass pane.
        .overlay(alignment: .bottom) {
            if !browser { Rectangle().fill(.primary.opacity(scheme == .dark ? 0.28 : 0.10)).frame(height: 0.5) }
        }
        .allowsHitTesting(false)
    }
}

/// Keep native refraction/blur at full strength. Fading a material reveals the
/// original sharp backdrop and is not equivalent to increasing glass clarity.
struct TahoeGlass: ViewModifier {
    var radius: CGFloat = TahoeDesign.windowRadius
    var enabled = true
    // Desktop chrome uses the native clear glass recipe rather than an
    // additional painted rim or opacity on the entire surface.
    var clear = false
    var transparency: Double? = nil
    @ObservedObject private var preferences = TahoePreferences.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let clarity = TahoeNumeric.value(transparency ?? preferences.value.panelGlass, in: 0...1)
        let neutral = preferences.value.appearance == "oled" ? Color.black : scheme == .dark ? Color(white: 0.16) : Color(white: 0.96)
        content.background {
            if enabled {
                if reduceTransparency || clarity == 0 {
                    RoundedRectangle(cornerRadius: radius).fill(neutral)
                } else if #available(iOS 26.0, *) {
                    Color.clear.glassEffect(
                        (clear || clarity > 0.85 ? Glass.clear : Glass.regular).tint(neutral.opacity(pow(1 - clarity, 2) * 0.7)),
                        in: RoundedRectangle(cornerRadius: radius))
                } else {
                    RoundedRectangle(cornerRadius: radius).fill(.regularMaterial)
                        .overlay { RoundedRectangle(cornerRadius: radius).fill(neutral.opacity(pow(1 - clarity, 2) * 0.7)) }
                }
            }
        }
    }
}

struct TahoeControlStyle: ButtonStyle {
    enum Variant { case neutral, accent, destructive, toolbar }
    enum Size: CaseIterable {
        case mini, small, regular, large, extraLarge
        @MainActor var height: CGFloat {
            if TahoePreferences.shared.comfortableControlsEnabled { return 44 }
            switch self { case .mini: return 28; case .small: return 32; case .regular: return 40; case .large: return 44; case .extraLarge: return 48 }
        }
        var radius: CGFloat { switch self { case .mini: return 4; case .small: return 5; case .regular: return 100; default: return 100 } }
    }
    var variant: Variant = .neutral
    var size: Size = .regular
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.fontSize, weight: .medium))
            .foregroundStyle(variant == .accent ? TahoeDesign.accentForeground : variant == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, size == .mini ? 7 : size == .small ? 10 : 16)
            .frame(minHeight: size.height)
            .modifier(TahoeButtonFeedback(pressed: configuration.isPressed,
                surface: true, radius: size.radius,
                tint: variant == .accent ? TahoeDesign.accent : variant == .destructive ? .red.opacity(0.12) : .clear))
    }

}

// Native ports of macos-components' switch/checkbox geometry and MacVue tokens.
struct TahoeSwitchStyle: ToggleStyle {
    var size: TahoeControlSize = .regular
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let trackHeight = min(24, size.height)
        return Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer(minLength: 16)
                Capsule().fill(configuration.isOn ? TahoeDesign.accent : Color.primary.opacity(0.16))
                    .frame(width: size.switchWidth, height: trackHeight)
                    .overlay {
                        Capsule().fill(.white.opacity(0.9)).frame(width: size.switchThumb.width, height: size.switchThumb.height)
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                            .offset(x: (configuration.isOn ? 1 : -1) * (size.switchWidth - size.switchThumb.width - (trackHeight - size.switchThumb.height)) / 2)
                    }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(TahoePressStyle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isOn)
            .opacity(enabled ? 1 : 0.5)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(SwitchToggleStyle()) }
    }
}

struct TahoeCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5.5)
                    .fill(configuration.isOn ? TahoeDesign.accent : Color.primary.opacity(0.08))
                    .frame(width: 16, height: 16)
                    .overlay {
                        if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                    }
                configuration.label
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(TahoePressStyle()).accessibilityValue(configuration.isOn ? "Selected" : "Not selected")
    }
}

struct TahoeToolbarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .regular))
                .frame(width: 44, height: 44).contentShape(Capsule())
        }.buttonStyle(TahoePressStyle(surface: true, radius: 100))
            .foregroundStyle(.secondary).accessibilityLabel(label).tahoeTooltip(label)
    }

}

/// macos_ui's bounded, collapsible sidebar pattern; native layout and gestures.
struct TahoeSidebar<Sidebar: View, Content: View>: View {
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let content: () -> Content
    @State private var width: CGFloat = 236
    @State private var initialWidth: CGFloat?
    @State private var showCompactSidebar = false
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if geometry.size.width >= 556 {
                        sidebar().frame(width: min(width, max(160, geometry.size.width - 280))).frame(maxHeight: .infinity, alignment: .top)
                            .background { Rectangle().fill(.regularMaterial).overlay { Rectangle().fill(TahoeDesign.window).opacity(0.78) } }
                        Color.clear.frame(width: 6)
                            .overlay { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5) }
                            .contentShape(Rectangle())
                            .gesture(DragGesture().onChanged { value in
                                if initialWidth == nil { initialWidth = width }
                                width = min(min(320, geometry.size.width - 280), max(160, (initialWidth ?? width) + value.translation.width))
                            }.onEnded { _ in initialWidth = nil })
                            .accessibilityLabel("Resize sidebar")
                            .accessibilityAdjustableAction { adjustment in
                                width = min(320, max(160, width + (adjustment == .increment ? 20 : -20)))
                            }
                    }
                    VStack(spacing: 0) {
                        if geometry.size.width < 556 {
                            HStack {
                                TahoeToolbarButton(symbol: "sidebar.left", label: "Show sidebar") { showCompactSidebar.toggle() }
                                Spacer()
                            }.padding(.horizontal, 8).frame(height: TahoePreferences.shared.comfortableControlsEnabled ? 48 : 32).background(TahoeDesign.window)
                        }
                        content().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if geometry.size.width < 556 && showCompactSidebar {
                    Color.black.opacity(0.12).onTapGesture { showCompactSidebar = false }
                    VStack(spacing: 0) {
                        HStack { Text(TahoeStrings.ui("Sidebar")).font(.system(size: 13, weight: .semibold)); Spacer(); TahoeToolbarButton(symbol: "xmark", label: "Close sidebar") { showCompactSidebar = false } }.padding(10)
                        sidebar()
                    }.frame(width: min(260, geometry.size.width - 48)).frame(maxHeight: .infinity).background(.regularMaterial)
                        .shadow(color: .black.opacity(0.16), radius: 10, x: 5)
                }
            }.onChange(of: geometry.size.width) { _, width in if width >= 556 { showCompactSidebar = false } }
        }
    }
}

private struct TahoeWindowVisibleKey: EnvironmentKey { static let defaultValue = true }
private struct TahoeWindowActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var tahoeWindowVisible: Bool { get { self[TahoeWindowVisibleKey.self] } set { self[TahoeWindowVisibleKey.self] = newValue } }
    var tahoeWindowActive: Bool { get { self[TahoeWindowActiveKey.self] } set { self[TahoeWindowActiveKey.self] = newValue } }
}

/// macos-components' selected/unfocused palette, shared by native sidebar rows.
private struct TahoeSidebarSelection: ViewModifier {
    var selected: Bool
    @Environment(\.tahoeWindowActive) private var active
    func body(content: Content) -> some View {
        content.foregroundStyle(selected && active ? TahoeDesign.accentForeground : .primary)
            .background(selected ? active ? TahoeDesign.accent : Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
extension View { func tahoeSidebarSelection(_ selected: Bool) -> some View { modifier(TahoeSidebarSelection(selected: selected)) } }

private struct TahoeTrafficInset: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues { var tahoeTrafficInset: CGFloat { get { self[TahoeTrafficInset.self] } set { self[TahoeTrafficInset.self] = newValue } } }


struct TahoeTitlebarActions {
    let drag: AnyGesture<DragGesture.Value>
    let zoom: () -> Void
}
private struct TahoeTitlebarActionsKey: EnvironmentKey { static let defaultValue: TahoeTitlebarActions? = nil }
extension EnvironmentValues {
    var tahoeTitlebarActions: TahoeTitlebarActions? {
        get { self[TahoeTitlebarActionsKey.self] }
        set { self[TahoeTitlebarActionsKey.self] = newValue }
    }
}
private struct TahoeWindowDragRegion: ViewModifier {
    @Environment(\.tahoeTitlebarActions) private var actions
    func body(content: Content) -> some View {
        content.background {
            if let actions {
                Color.clear.contentShape(Rectangle()).gesture(actions.drag)
                    .onTapGesture(count: 2, perform: actions.zoom)
            }
        }
    }
}
extension View { func tahoeWindowDragRegion() -> some View { modifier(TahoeWindowDragRegion()) } }

/// Native regular glass remains fully composited; blur, tint and rim define it.
struct TahoeLauncherMaterial: ViewModifier {
    @ObservedObject private var preferences = TahoePreferences.shared
    @Environment(\.accessibilityReduceTransparency) private var opaque
    func body(content: Content) -> some View {
        let clarity = TahoeNumeric.value(preferences.value.launcherGlass, in: 0...1)
        content.background {
            if opaque || clarity == 0 { RoundedRectangle(cornerRadius: 26).fill(preferences.value.appearance == "oled" ? Color.black : Color(white: 0.2)) }
            else if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(Color(white: 0.55).opacity((1 - clarity) * 0.25)), in: RoundedRectangle(cornerRadius: 26))
            } else { RoundedRectangle(cornerRadius: 26).fill(.regularMaterial) }
        }
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.black.opacity(0.28), lineWidth: 1)
            .overlay { RoundedRectangle(cornerRadius: 26).inset(by: 1).strokeBorder(.white.opacity(0.30), lineWidth: 0.5) }.allowsHitTesting(false) }
    }
}


/// Browser-only capsules use the system's optical material instead of a flat
/// simulated grey fill. This modifier keeps accessibility's opaque preference
/// authoritative and does not change the desktop's other window controls.
private struct TahoeBrowserPillMaterial: ViewModifier {
    var selected = false
    var interactive = false
    @ObservedObject private var preferences = TahoePreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.tahoeWindowActive) private var active
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency || TahoeNumeric.value(preferences.value.browserGlass, in: 0...1) == 0 {
                content.background {
                    Capsule().fill(scheme == .dark ? Color(white: selected ? 0.34 : 0.26) : Color(white: selected ? 0.93 : 0.88))
                }
            } else if #available(iOS 26.0, *) {
                content.glassEffect(
                    .regular.tint(.white.opacity((selected ? 0.15 : 0.025) * (1 - TahoeNumeric.value(preferences.value.browserGlass, in: 0...1) * 0.75)))
                        .interactive(interactive && enabled && active && !reduceMotion),
                    in: Capsule())
            } else {
                content.background { Capsule().fill(.regularMaterial) }
            }
        }
            .overlay {
                Capsule().fill(
                    (scheme == .dark ? Color.white : Color.black)
                        .opacity(selected ? (scheme == .dark ? 0.055 : 0.025) : 0.012)
                )
                .allowsHitTesting(false)
            }
            .overlay {
                Capsule().strokeBorder(
                    Color.white.opacity(contrast == .increased ? 0.32 : selected ? 0.19 : 0.105),
                    lineWidth: contrast == .increased ? 0.9 : 0.55
                ).allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(selected ? 0.13 : 0.065), radius: selected ? 2.2 : 1.1, y: 0.6)
    }
}
extension View {
    func tahoeBrowserPill(selected: Bool = false, interactive: Bool = false) -> some View {
        modifier(TahoeBrowserPillMaterial(selected: selected, interactive: interactive))
    }
    @ViewBuilder func tahoeBrowserTab(selected: Bool) -> some View {
        if selected { self.tahoeBrowserPill(selected: true, interactive: true) }
        else { self.background { Capsule().fill(Color.primary.opacity(0.035)) } }
    }
}


/// One interaction vocabulary for buttons without changing their label layout.
/// Rows/icons stay lightweight; only toolbar/action controls own glass surfaces.
struct TahoePressStyle: ButtonStyle {
    var surface = false
    var radius: CGFloat = 7
    var scale: CGFloat = 0.97
    var pointerEffect = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(TahoeButtonFeedback(pressed: configuration.isPressed,
            surface: surface, radius: radius, pressedScale: scale, pointerEffect: pointerEffect))
    }
}

private struct TahoeButtonFeedback: ViewModifier {
    var pressed: Bool
    var surface: Bool
    var radius: CGFloat
    var tint: Color = .clear
    var pressedScale: CGFloat = 0.97
    var pointerEffect = true
    @State private var hovered = false
    @ObservedObject private var preferences = TahoePreferences.shared
    @Environment(\.isEnabled) private var enabled
    @Environment(\.tahoeWindowActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var down: Bool { enabled && pressed }
    private var over: Bool { enabled && active && hovered }
    func body(content: Content) -> some View {
        content
            .modifier(TahoeControlSurface(enabled: surface, radius: radius, tint: tint,
                interactive: enabled && active && !reduceMotion))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(down ? 0.13 : over ? 0.06 : 0))
                    .allowsHitTesting(false)
            }
            .brightness(down ? -0.035 : 0)
            .scaleEffect(down && !reduceMotion ? pressedScale : 1)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: radius, style: .continuous))
            .hoverEffect(.highlight, isEnabled: pointerEffect && enabled && active && !surface && !reduceMotion)
            .onHover { hovered = $0 }
            .onChange(of: active) { _, active in if !active { hovered = false } }
            .onDisappear { hovered = false }
            .sensoryFeedback(.impact(weight: .light), trigger: down) { _, pressed in
                pressed && preferences.value.touchFeedback != false
            }
            .animation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.86), value: down)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: over)
    }
}

/// Native glass after layout, with an opaque accessibility path and iOS 17 fallback.
struct TahoeControlSurface: ViewModifier {
    var enabled = true
    var radius: CGFloat = 100
    var tint: Color = .clear
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let clarity = 1.0
        Group {
            if !enabled { content }
            else if opaque || clarity == 0 {
                content.background { shape.fill(TahoeDesign.group).overlay { shape.fill(tint) } }
                    .overlay { shape.strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5).allowsHitTesting(false) }
            } else if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            } else {
                content.background { shape.fill(.regularMaterial).overlay { shape.fill(tint) } }
                    .overlay { shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.16 : 0.65), lineWidth: 0.5).allowsHitTesting(false) }
                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
            }
        }
    }
}

/// Keep related glass controls in one local sampling group, without merging gaps.
private struct TahoeGlassGroup: ViewModifier {
    var spacing: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: spacing) { content } }
        else { content }
    }
}
extension View {
    func tahoeGlassGroup(spacing: CGFloat = 0) -> some View { modifier(TahoeGlassGroup(spacing: spacing)) }
}

/// Standalone browser capsules press as one surface; grouped commands share a pill.
struct TahoeBrowserButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.tahoeBrowserPill(interactive: true)
            .modifier(TahoeButtonFeedback(pressed: configuration.isPressed, surface: false, radius: 100))
    }
}
