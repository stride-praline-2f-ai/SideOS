import SwiftUI

enum TahoeAccent: String, Codable, CaseIterable {
    case blue, purple, pink, red, orange, green, graphite
    var color: Color {
        switch self {
        case .blue: return Color(red: 0, green: 0.533, blue: 1)
        case .purple: return Color(red: 0.796, green: 0.188, blue: 0.878)
        case .pink: return .pink
        case .red: return Color(red: 1, green: 0.22, blue: 0.235)
        case .orange: return .orange
        case .green: return Color(red: 0.204, green: 0.78, blue: 0.349)
        case .graphite: return .gray
        }
    }
}

/// Exact opaque browser-chrome tones. Independent of Liquid Glass transparency.
/// The default is the previous 0.16 white background (approximately #292929).
enum TahoeBrowserToolbarShade: String, Codable, CaseIterable, Identifiable {
    case standard, charcoal, graphite, deepBlack, nearBlack, midnight, oledBlack

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Standard"
        case .charcoal: return "Charcoal"
        case .graphite: return "Graphite"
        case .deepBlack: return "Deep Black"
        case .nearBlack: return "Near Black"
        case .midnight: return "Midnight"
        case .oledBlack: return "OLED Black"
        }
    }
    var grey: Int {
        switch self {
        case .standard: return 41
        case .charcoal: return 34
        case .graphite: return 26
        case .deepBlack: return 18
        case .nearBlack: return 12
        case .midnight: return 6
        case .oledBlack: return 0
        }
    }
    var color: Color { Color(white: Double(grey) / 255) }
    var hex: String { String(format: "#%02X%02X%02X", grey, grey, grey) }
}

struct TahoeSettings: Codable, Equatable {
    // A unified, neutral Safari-like glass surface. Higher = clearer.
    static let safariMenuTransparency = 0.72
    static let safariBrowserTransparency = 0.72
    var chatGPTTabs: Bool?
    var restoreWorkTabs: Bool?
    var remoteSuggestions: Bool?
    var comfortableControls: Bool?
    var desktopDensity: String?
    var touchFeedback: Bool?
    var compactDesktop: Bool { desktopDensity != "standard" }
    var displayLayout: String?
    var displayLayoutMode: String {
        guard let displayLayout, ["automatic", "duo", "desktop"].contains(displayLayout) else { return "automatic" }
        return displayLayout
    }
    var residentPageLimit: Int?
    var separateDesktop: Bool?
    var downloadToDocuments: Bool?
    var saveHistory: Bool?
    var spaceNames: [String: String]?
    var nativePins: [String]?
    var recentNativeApps: [String]?
    var adapterFeed: String?
    var adapterPublicKey: String?
    var siteMediaChoices: [String: String]?
    var fileFavorites: [String]?
    var recentFileLocations: [String]?
    var blockTrackers: Bool?
    var contentBlockingExceptions: [String]?
    var spaceWallpapers: [String: String]?
    var searchProvider: TahoeSearchProvider?
    var appSpaceAssignments: [String: Int]?
    var chatTabsEnabled: Bool { chatGPTTabs ?? true }
    var appearance = "system"
    var accent = TahoeAccent.blue
    var wallpaper = "coast"
    var dockSize = 48.0
    var magnification = false
    var autoHideDock = false
    var desktopIcons = true
    var restoreWorkspace = true
    // Retained solely to decode older saved settings; website identity replaces it.
    var desktopBrowsing = true
    var websiteIdentity: TahoeWebsiteIdentity?
    var browserIdentity: TahoeWebsiteIdentity {
        get { websiteIdentity ?? .macOSEnhanced }
        set { websiteIdentity = newValue }
    }
    var dockTransparency: Double?
    var dockGlassStyle: String?
    var nativeDockGlassStyle: String {
        get {
            if let dockGlassStyle, ["clear", "regular", "solid"].contains(dockGlassStyle) { return dockGlassStyle }
            return dockTransparency == 0 ? "solid" : "clear"
        }
        set { dockGlassStyle = newValue }
    }
    var menuTransparency: Double?
    var browserTransparency: Double?
    var browserGlass: Double { get { browserTransparency ?? Self.safariBrowserTransparency } set { browserTransparency = newValue } }
    // Optional for backwards-compatible decoding of existing installed settings.
    // Do not migrate or reset glass or other saved choices when upgrading.
    var browserToolbarShade: TahoeBrowserToolbarShade?
    var browserBarShade: TahoeBrowserToolbarShade {
        get { browserToolbarShade ?? .standard }
        set { browserToolbarShade = newValue }
    }
    var panelTransparency: Double?
    // Independent glass levels for the Applications launcher and the
    // dropdowns attached to the desktop menu bar.
    var launcherTransparency: Double?
    var menuDropdownTransparency: Double?
    var clearDesktopMenu: Bool?
    var automaticDockSizing: Bool?
    var overlayGuestControls: Bool?
    var hiddenDockKinds: [String]?
    var dockGlass: Double { get { dockTransparency ?? 0.65 } set { dockTransparency = newValue } }
    var menuGlass: Double { get { menuTransparency ?? Self.safariMenuTransparency } set { menuTransparency = newValue } }
    var panelGlass: Double { get { panelTransparency ?? 0 } set { panelTransparency = newValue } }
    var launcherGlass: Double { get { launcherTransparency ?? 0.45 } set { launcherTransparency = newValue } }
    var menuDropdownGlass: Double { get { menuDropdownTransparency ?? 0.45 } set { menuDropdownTransparency = newValue } }
    var desktopMenuIsClear: Bool { get { clearDesktopMenu ?? true } set { clearDesktopMenu = newValue } }
    var dockFitsAutomatically: Bool { get { automaticDockSizing ?? true } set { automaticDockSizing = newValue } }
    var guestControlsOverlay: Bool { get { overlayGuestControls ?? true } set { overlayGuestControls = newValue } }
    var customAccent: TahoeAccentComponents?
    var accentColor: Color { customAccent?.color ?? accent.color }
}

struct TahoeAccentComponents: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var color: Color { Color(red: TahoeNumeric.value(red, in: 0...1), green: TahoeNumeric.value(green, in: 0...1), blue: TahoeNumeric.value(blue, in: 0...1)) }
    init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.red = Double(red); self.green = Double(green); self.blue = Double(blue)
    }
}

@MainActor final class TahoePreferences: ObservableObject {
    static let shared = TahoePreferences()
    @Published var value: TahoeSettings {
        didSet {
            guard value != oldValue else { return }
            pendingSave?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.save() }
            pendingSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
    var comfortableControlsEnabled: Bool { value.comfortableControls ?? TahoeDisplayMetrics.shared.current.usesTouchLayout }
    private var pendingSave: DispatchWorkItem?
    func save() {
        pendingSave?.cancel(); pendingSave = nil
        if let data = try? JSONEncoder().encode(value) {
            let defaults = UserDefaults.standard
            if let previous = defaults.data(forKey: "TahoeSettings.v2"), (try? JSONDecoder().decode(TahoeSettings.self, from: previous)) != nil { defaults.set(previous, forKey: "TahoeSettings.v2.previous") }
            defaults.set(data, forKey: "TahoeSettings.v2")
        }
    }
    private static func recover(_ data: Data?) -> TahoeSettings? {
        guard let data else { return nil }
        if let value = try? JSONDecoder().decode(TahoeSettings.self, from: data) { return value }
        guard let source = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseline = try? JSONEncoder().encode(TahoeSettings()),
              var merged = try? JSONSerialization.jsonObject(with: baseline) as? [String: Any] else { return nil }
        // Recover valid fields independently; one invalid old enum or missing
        // required field must not reset wallpaper, profile and Dock choices.
        for (key, value) in source {
            var candidate = merged; candidate[key] = value
            guard let bytes = try? JSONSerialization.data(withJSONObject: candidate), (try? JSONDecoder().decode(TahoeSettings.self, from: bytes)) != nil else { continue }
            merged = candidate
        }
        guard let bytes = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(TahoeSettings.self, from: bytes)
    }
    init() {
        let defaults = UserDefaults.standard
        let saved = Self.recover(defaults.data(forKey: "TahoeSettings.v2")) ?? Self.recover(defaults.data(forKey: "TahoeSettings.v2.previous"))
        var settings = saved ?? TahoeSettings()
        // On upgrade, preserve the user's existing panel clarity in each
        // newly independent control. Afterwards, sliders never track each other.
        let migrateIndependentGlass = settings.launcherTransparency == nil || settings.menuDropdownTransparency == nil
        if settings.launcherTransparency == nil { settings.launcherGlass = settings.panelGlass }
        if settings.menuDropdownTransparency == nil { settings.menuDropdownGlass = settings.panelGlass }
        let dockMigrationKey = "TahoeDockLabelOnly.v1"
        let migrateDock = !defaults.bool(forKey: dockMigrationKey)
        if migrateDock { settings.magnification = false }
        // One-time migration for an in-place IPA upgrade. Only the three
        // Safari-chrome preferences are reset; all unrelated user settings
        // (wallpaper, accounts, workspace, bookmarks, etc.) remain intact.
        // Once migrated, users may adjust these sliders normally.
        let migrationKey = "TahoeSafariChromeDefaults.v1"
        if !defaults.bool(forKey: migrationKey) {
            settings.menuGlass = TahoeSettings.safariMenuTransparency
            settings.browserGlass = TahoeSettings.safariBrowserTransparency
            if settings.clearDesktopMenu == nil { settings.desktopMenuIsClear = true }
            value = settings
            if let data = try? JSONEncoder().encode(settings) {
                defaults.set(data, forKey: "TahoeSettings.v2")
                defaults.set(true, forKey: migrationKey)
            }
        } else {
            value = settings
        }
        if migrateDock || migrateIndependentGlass {
            if let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: "TahoeSettings.v2")
                if migrateDock { defaults.set(true, forKey: dockMigrationKey) }
            }
        }
    }
    var colorScheme: ColorScheme? { value.appearance == "system" ? nil : ["dark", "oled"].contains(value.appearance) ? .dark : .light }
}
