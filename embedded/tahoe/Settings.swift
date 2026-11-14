import SwiftUI
import UniformTypeIdentifiers

struct TahoeSettingsView: View {
    @ObservedObject private var preferences = TahoePreferences.shared
    @EnvironmentObject private var workspace: TahoeWorkspace
    @State private var search = ""
    private var selection: String { workspace.settingsSection }
    @State private var importingWallpaper = false
    @ObservedObject private var wallpaperPhoto = TahoeWallpaperPhoto.shared
    private let sections: [(String, String, Color)] = [("Appearance", "circle.lefthalf.filled", .black), ("Desktop & Dock", "dock.rectangle", .blue), ("Browser", "safari", .blue), ("Windows", "macwindow", .gray), ("Built-in JIT", "bolt.shield", .orange), ("Wireless Display", "display.2", .indigo), ("Storage & Recovery", "externaldrive", .teal), ("About", "info.circle.fill", .gray)]
    var body: some View {
        TahoeSidebar {
            VStack(alignment: .leading, spacing: 4) {
                TahoeSearchField(text: $search).padding(.bottom, 5)
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 36)).foregroundStyle(.secondary)
                    VStack(alignment: .leading) { Text(TahoeStrings.ui("Your Desktop")).font(.system(size: 13, weight: .semibold)); Text(TahoeStrings.ui(TahoeDisplayMetrics.shared.snapshot.phone ? "On this iPhone" : "On this iPad")).font(.system(size: 11)).foregroundStyle(.secondary) }
                }.padding(.vertical, 16).padding(.horizontal, 6)
                ForEach(sections.filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) }, id: \.0) { title, symbol, color in
                    Button { workspace.selectSettings(title) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: symbol).frame(width: 22, height: 22).foregroundStyle(.white).background(color.gradient, in: RoundedRectangle(cornerRadius: 5))
                            Text(TahoeStrings.ui(title)); Spacer()
                        }.padding(.horizontal, 8).frame(height: preferences.comfortableControlsEnabled ? 44 : 30)
                            .foregroundStyle(.primary)
                            .background(selection == title ? Color.primary.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(TahoePressStyle()).accessibilityIdentifier("settings-section-\(title)")
                }
                Spacer()
            }.font(.system(size: 13)).padding(10)
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsContent
                }.padding(20).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }.background(TahoeDesign.window)
        }
        .fileImporter(isPresented: $importingWallpaper, allowedContentTypes: [.image]) { result in
            Task {
                do { try await wallpaperPhoto.importImage(result.get()) }
                catch { workspace.error = "Wallpaper could not be imported: \(error.localizedDescription)" }
            }
        }
    }
    @ViewBuilder private var settingsContent: some View {
        switch selection {
        case "Appearance": appearance
        case "Desktop & Dock": dock
        case "Browser": browser
        case "Windows": windows
        case "Built-in JIT": TahoeJITSetupGuide()
        case "Wireless Display": TahoeDisplaySettings()
        case "Storage & Recovery": TahoeStorageSettings(workspace: workspace)
        default: about
        }
    }
    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 116))], alignment: .leading, spacing: 16) {
                ForEach(["light", "dark", "oled", "system"], id: \.self) { value in
                    Button { preferences.value.appearance = value } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                RoundedRectangle(cornerRadius: 5).fill(value == "oled" ? Color.black : value == "dark" ? Color(white: 0.18) : .white.opacity(0.9)).padding(.leading, 18).padding(.top, 14).padding(.trailing, 8).padding(.bottom, 8)
                                if value == "system" { Rectangle().fill(.black.opacity(0.55)).frame(width: 46).frame(maxWidth: .infinity, alignment: .trailing) }
                            }.frame(width: 100, height: 68).clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(preferences.value.appearance == value ? TahoeDesign.accent : .clear, lineWidth: 3) }
                            Text(value == "oled" ? "OLED Black" : value.capitalized).font(.system(size: 12))
                        }
                    }.buttonStyle(TahoePressStyle())
                }
            }
            Text("OLED Black uses pure black for SideOS’s solid backgrounds and browser toolbar. Websites and hosted apps keep control of their own content.").font(.caption).foregroundStyle(.secondary)
            card {
                HStack {
                    Text(TahoeStrings.ui("Accent colour")); Spacer()
                    ForEach(TahoeAccent.allCases, id: \.self) { accent in
                        Button { preferences.value.accent = accent; preferences.value.customAccent = nil } label: {
                            Circle().fill(accent.color).frame(width: 19, height: 19)
                                .overlay { if preferences.value.accent == accent && preferences.value.customAccent == nil { Circle().strokeBorder(.white, lineWidth: 2).padding(4) } }
                        }.buttonStyle(TahoePressStyle()).accessibilityLabel(accent.rawValue.capitalized)
                    }
                }
            }
            ColorPicker("Custom accent colour", selection: Binding(get: { preferences.value.accentColor }, set: { preferences.value.customAccent = TahoeAccentComponents($0) }), supportsOpacity: false)
                .font(.system(size: 13))
            Text(TahoeStrings.ui("Wallpaper")).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 12) {
                ForEach(["coast", "dawn", "graphite"], id: \.self) { style in
                    Button { preferences.value.wallpaper = style } label: {
                        VStack(spacing: 8) {
                            TahoeWallpaper(style: style).frame(width: 116, height: 76).clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(preferences.value.wallpaper == style ? TahoeDesign.accent : .clear, lineWidth: 3) }
                            Text(style == "coast" ? "Golden Gate" : style.capitalized).font(.system(size: 12))
                        }
                    }.buttonStyle(TahoePressStyle())
                }
            }
            HStack {
                Button(TahoeStrings.ui("Choose Image…")) { importingWallpaper = true }.buttonStyle(TahoeControlStyle()).disabled(wallpaperPhoto.loading)
                if wallpaperPhoto.image != nil { Button(TahoeStrings.ui("Use My Image")) { preferences.value.wallpaper = "custom" }.buttonStyle(TahoeControlStyle()) }
                if wallpaperPhoto.loading { TahoeSpinner() }
            }
            Text(TahoeStrings.ui("Glass surfaces follow Reduce Transparency and Reduce Motion in iPad accessibility settings.")).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var dock: some View {
        VStack(spacing: 20) {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(TahoeStrings.ui("Dock icon size")); Spacer(); Text("\(Int(preferences.value.dockSize)) pt").foregroundStyle(.secondary) }
                    HStack(spacing: 14) {
                        TahoeSlider(value: $preferences.value.dockSize, range: 24...128, step: 2, ticks: true, label: "Dock icon size")
                        TahoeStepper(value: $preferences.value.dockSize, range: 24...128, step: 2, label: "Dock icon size")
                    }
                    Divider()
                    Toggle(TahoeStrings.ui("Magnification"), isOn: $preferences.value.magnification).toggleStyle(TahoeSwitchStyle())
                    Divider()
                    Toggle(TahoeStrings.ui("Automatically hide the Dock"), isOn: $preferences.value.autoHideDock).toggleStyle(TahoeSwitchStyle())
                }
            }
            card {
                VStack(spacing: 12) {
                    Toggle(TahoeStrings.ui("Fit Dock icons to available space"), isOn: Binding(get: { preferences.value.dockFitsAutomatically }, set: { preferences.value.dockFitsAutomatically = $0 })).toggleStyle(TahoeSwitchStyle())
                    Toggle(TahoeStrings.ui("Fully transparent menu bar on desktop and windowed apps"), isOn: Binding(get: { preferences.value.desktopMenuIsClear }, set: { preferences.value.desktopMenuIsClear = $0 })).toggleStyle(TahoeSwitchStyle())
                    Picker("Dock Liquid Glass", selection: Binding(get: { preferences.value.nativeDockGlassStyle }, set: { preferences.value.nativeDockGlassStyle = $0 })) {
                        Text("Native Clear").tag("clear")
                        Text("Native Regular").tag("regular")
                        Text("Solid").tag("solid")
                    }.pickerStyle(.segmented)
                    Text("Uses Apple's system Liquid Glass material with no simulated tint or opacity layer. Reduce Transparency takes priority.").font(.caption).foregroundStyle(.secondary)
                    transparency("Menu bar transparency", value: Binding(get: { preferences.value.menuGlass }, set: { preferences.value.menuGlass = $0 }))
                    transparency("Menu bar dropdown transparency", value: Binding(get: { preferences.value.menuDropdownGlass }, set: { preferences.value.menuDropdownGlass = $0 }))
                    transparency("Applications launcher transparency", value: Binding(get: { preferences.value.launcherGlass }, set: { preferences.value.launcherGlass = $0 }))
                    transparency("Other panels and menus transparency", value: Binding(get: { preferences.value.panelGlass }, set: { preferences.value.panelGlass = $0 }))
                    Toggle(TahoeStrings.ui("Overlay traffic lights on native apps"), isOn: Binding(get: { preferences.value.guestControlsOverlay }, set: { preferences.value.guestControlsOverlay = $0 })).toggleStyle(TahoeSwitchStyle())
                    Text("Menu bar transparency changes only the top strip; menu bar dropdown transparency changes only its File/Edit/View and other dropdowns. The Applications launcher and other panels/menus have separate controls. Reduce Transparency in iPad accessibility settings takes priority. Native-app traffic-light overlays may cover their own controls.").font(.caption).foregroundStyle(.secondary)
                }
            }
            card { Toggle(TahoeStrings.ui("Show desktop icons"), isOn: $preferences.value.desktopIcons).toggleStyle(TahoeCheckboxStyle()) }
        }
    }
    private func transparency(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(TahoeStrings.ui(title)); Spacer(); Text("\(Int(value.wrappedValue * 100))%").foregroundStyle(.secondary) }
            TahoeSlider(value: value, range: 0...1, step: 0.05, label: title)
        }
    }
    /// Seven solid dark-chrome presets. Swatches adapt to Settings window size
    /// and immediately update every browser without touching live WKWebViews.
    private var browserToolbarShadePicker: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(TahoeStrings.ui("Browser toolbar colour")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(preferences.value.browserBarShade.hex)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                    ForEach(TahoeBrowserToolbarShade.allCases) { shade in
                        let selected = preferences.value.browserBarShade == shade
                        Button { preferences.value.browserBarShade = shade } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(shade.color)
                                    .frame(height: 37)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(selected ? TahoeDesign.accent : Color.primary.opacity(0.24),
                                                          lineWidth: selected ? 2.5 : 1)
                                    }
                                    .overlay {
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                Text(shade.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(height: 28)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(4)
                            .background(selected ? TahoeDesign.accent.opacity(0.08) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(shade.title), \(shade.hex)")
                        .accessibilityIdentifier("browser-toolbar-shade-\(shade.rawValue)")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                HStack(spacing: 11) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                    Text(TahoeStrings.ui("example.com"))
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .tahoeBrowserPill()
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "square.on.square")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.white)
                .padding(10)
                .background(preferences.value.browserBarShade.color,
                            in: RoundedRectangle(cornerRadius: 12))
                .environment(\.colorScheme, .dark)
                .accessibilityLabel("Browser toolbar colour preview")
                Text(TahoeStrings.ui("Dark appearance only. Standard preserves the original shade; OLED Black is pure #000000. The background stays solid at every glass transparency setting."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 20) {
            browserToolbarShadePicker
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Isolated Browser", systemImage: "lock.shield").font(.headline)
                    Text("For logins that need separation from hosted apps, use the separately installed SideOS Browser. It has its own iOS process and data container, checks its signed sharing/debug entitlements, and does not import SideOS cookies.").font(.callout)
                    Button("Open Isolated Browser") { TahoeIsolatedBrowserLink.open() }.buttonStyle(TahoeControlStyle())
                    Text("The embedded browser's profiles and Private mode are not a security boundary against native code running inside LiveContainer. The separate browser opens in its own iPadOS window.").font(.caption).foregroundStyle(.secondary)
                }
            }
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(TahoeStrings.ui("ChatGPT chat tabs"), isOn: Binding(get: { preferences.value.chatTabsEnabled }, set: { workspace.setChatTabsEnabled($0) }))
                        .toggleStyle(TahoeCheckboxStyle())
                    Text(TahoeStrings.ui("On chatgpt.com, use Chats to open or switch conversations. Two or more chats reveal the integrated tab row. Split view keeps two conversations visible."))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(TahoeStrings.ui("Google search suggestions"), isOn: Binding(get: { preferences.value.remoteSuggestions ?? true }, set: { preferences.value.remoteSuggestions = $0 }))
                        .toggleStyle(TahoeCheckboxStyle())
                    Picker(TahoeStrings.ui("Search provider"), selection: Binding(get: { preferences.value.searchProvider ?? .google }, set: { preferences.value.searchProvider = $0 })) {
                        ForEach(TahoeSearchProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text(TahoeStrings.ui("When enabled, search terms are sent to Google while you type. Suggestions use no cookies and are disabled in Private browsing. Searching still works when suggestions are off."))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(TahoeStrings.ui("Basic tracker blocking"), isOn: Binding(get: { preferences.value.blockTrackers ?? false }, set: { preferences.value.blockTrackers = $0 })).toggleStyle(TahoeCheckboxStyle())
                    Text(TahoeStrings.ui("Optional bundled rules block a small set of known tracker domains. Changes apply on navigation. Website Information can exempt a site.")).font(.caption).foregroundStyle(.secondary)
                    Toggle(TahoeStrings.ui("Save browsing history"), isOn: Binding(get: { preferences.value.saveHistory ?? true }, set: { preferences.value.saveHistory = $0 })).toggleStyle(TahoeCheckboxStyle())
                    Toggle(TahoeStrings.ui("Save downloads in Documents"), isOn: Binding(get: { preferences.value.downloadToDocuments ?? false }, set: { preferences.value.downloadToDocuments = $0 })).toggleStyle(TahoeCheckboxStyle())
                }
            }
            card { transparency("Browser control glass transparency", value: Binding(get: { preferences.value.browserGlass }, set: { preferences.value.browserGlass = $0 })) }
            Text(TahoeStrings.ui("The seven colour presets change only the solid browser toolbar and tab-strip backing. The existing glass slider adjusts browser controls, not the background. The toolbar does not reveal webpage content when scrolling.")).font(.caption).foregroundStyle(.secondary)
            TahoeSettingsGroup(title: "Website Device Identity") {
                TahoeRadioGroup(options: TahoeWebsiteIdentity.allCases.map { TahoeChoice(id: $0.rawValue, title: $0.title) },
                                selection: Binding(get: { preferences.value.browserIdentity.rawValue },
                                                   set: { if let identity = TahoeWebsiteIdentity(rawValue: $0) { preferences.value.browserIdentity = identity } }),
                                label: "Website Device Identity")
            }
            Text(TahoeStrings.ui("New tabs use this identity. Choose another for an open tab from Browser Options. Changing an open tab reloads its page and discards that tab's back history.")).font(.caption).foregroundStyle(.secondary)
            Text(TahoeStrings.ui("macOS Safari requests desktop websites using a Mac Safari identity. Enhanced Spoofing also masks a few JavaScript device signals, but cannot conceal WebKit or supply Mac-only features; some websites may misbehave.")).font(.caption).foregroundStyle(.secondary)
            Text(TahoeStrings.ui("Websites follow the light, dark or system appearance chosen in SideOS Appearance settings when the site supports colour schemes.")).font(.caption).foregroundStyle(.secondary)
            Text(TahoeStrings.ui("Bookmarks")).font(.system(size: 13, weight: .semibold))
            card {
                VStack(spacing: 12) {
                    if workspace.bookmarks.isEmpty { Text(TahoeStrings.ui("Use Browser Options → Add Bookmark on an open website.")).foregroundStyle(.secondary) }
                    ForEach(workspace.bookmarks) { link in
                        HStack {
                            VStack(alignment: .leading) { Text(link.title); Text(link.url.host ?? "").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button { workspace.removeBookmark(link.id) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }.buttonStyle(TahoePressStyle()).accessibilityLabel("Remove \(link.title)")
                        }
                    }
                }
            }
            Button(TahoeStrings.ui("Open Downloads")) { workspace.open(.downloads) }.buttonStyle(TahoeControlStyle())
            TahoeAdapterUpdateSettings()
        }
    }
    private var windows: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                Picker("Desktop density", selection: Binding(get: { preferences.value.compactDesktop ? "compact" : "standard" }, set: { preferences.value.desktopDensity = $0 })) {
                    Text("Compact").tag("compact")
                    Text("Standard").tag("standard")
                }.pickerStyle(.segmented)
                Text("Compact uses smaller Dock icons and tighter browser chrome, with touch targets kept usable. New windows open centered above the Dock. Existing window positions are preserved.").font(.caption).foregroundStyle(.secondary)
            }
            card { Toggle("Touch feedback", isOn: Binding(get: { preferences.value.touchFeedback ?? true }, set: { preferences.value.touchFeedback = $0 })).toggleStyle(TahoeSwitchStyle()) }
            card { Toggle(TahoeStrings.ui("Comfortable touch controls"), isOn: Binding(get: { preferences.comfortableControlsEnabled }, set: { preferences.value.comfortableControls = $0 })).toggleStyle(TahoeCheckboxStyle()) }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Display layout", selection: Binding(get: { preferences.value.displayLayoutMode }, set: { preferences.value.displayLayout = $0 })) {
                        Text("Automatic").tag("automatic")
                        Text("iPhone Duo · iPad-style inner screen").tag("duo")
                        Text("Desktop").tag("desktop")
                    }
                    Text("The inner screen keeps the iPad desktop appearance, controls and window behavior, fitted to its native window size and safe areas. The outer screen uses the compact phone layout.").font(.caption).foregroundStyle(.secondary)
                }
            }
            card { Toggle(TahoeStrings.ui("Restore desktop windows at startup"), isOn: $preferences.value.restoreWorkspace).toggleStyle(TahoeCheckboxStyle()) }
            Text(TahoeStrings.ui("Window positions, Spaces and browser addresses are saved. Browser pages restore automatically, with selected pages first and background work limited. Private pages are never saved. SideInstaller reopens when its saved window is visible. Third-party native apps are never automatically relaunched.")).font(.callout).foregroundStyle(.secondary)
            card { Toggle(TahoeStrings.ui("Restore Work profile tabs"), isOn: Binding(get: { preferences.value.restoreWorkTabs ?? false }, set: { preferences.value.restoreWorkTabs = $0 })).toggleStyle(TahoeCheckboxStyle()) }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(TahoeStrings.ui("Use a separate Desktop folder"), isOn: Binding(get: { preferences.value.separateDesktop ?? false }, set: { preferences.value.separateDesktop = $0 })).toggleStyle(TahoeCheckboxStyle())
                    Text(TahoeStrings.ui("Existing documents stay in Documents. Enable this to show Finder → Desktop instead; this setting does not move or delete your files.")).font(.caption).foregroundStyle(.secondary)
                    Stepper("Resident browser page budget: \(preferences.value.residentPageLimit ?? 16)", value: Binding(get: { preferences.value.residentPageLimit ?? 16 }, set: { preferences.value.residentPageLimit = $0 }), in: 4...40)
                    Text(TahoeStrings.ui("Eligible background pages can sleep above this budget. Visible pages, drafts, edited forms, media and active downloads are protected. Memory pressure temporarily reduces the budget.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TahoeStrings.ui("Fullscreen")).fontWeight(.semibold)
                    Text(TahoeStrings.ui("Seamless fullscreen preserves other sessions. Window → Performance Fullscreen asks before unloading inactive browser pages. Active downloads are retained. Unsaved page state and back history are lost for unloaded pages."))
                }
            }
            HStack {
                Button(TahoeStrings.ui("Window Overview")) { workspace.present(.overview) }.buttonStyle(TahoeControlStyle())
                Button(TahoeStrings.ui("Save Workspace Now")) { workspace.saveWorkspace() }.buttonStyle(TahoeControlStyle())
            }
        }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            TahoeAboutView()
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(TahoeStrings.ui("Source projects")).fontWeight(.semibold)
                    Text(TahoeStrings.ui("macos-ui · macos-components · MacVue · macos_ui"))
                    TahoeDisclosure(title: "About the source adaptations") {
                        Text(TahoeStrings.ui("Native adaptations with retained source attribution. The desktop runs on iPadOS. Browser-specific rendering and macOS-only APIs have native replacements where supported."))
                    }
                }
            }
            Button(TahoeStrings.ui("LiveContainer & SideInstaller…")) { workspace.showManagement = true }.buttonStyle(TahoeControlStyle())
        }
    }
    private func card<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        TahoeSettingsGroup(content: content)
    }
}

struct TahoeAboutView: View {
    @ObservedObject private var display = TahoeDisplayMetrics.shared
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "desktopcomputer").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(TahoeDesign.accent)
            Text(TahoeStrings.ui("SideOS")).font(.system(size: 26, weight: .bold))
            Text(TahoeReleaseInfo.label).font(.caption.monospaced()).textSelection(.enabled)
            Text("A native desktop workspace on \(UIDevice.current.systemName)").font(.system(size: 13)).foregroundStyle(.secondary)
            TahoeUpstreamCredits()
            Divider().frame(width: 200)
            Text("\(UIDevice.current.model) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)").font(.system(size: 12))
            Text("\(ProcessInfo.processInfo.activeProcessorCount) CPU cores · \(ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)) physical memory").font(.system(size: 12)).foregroundStyle(.secondary)
            Text(display.diagnostics).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Text(TahoeReleaseInfo.runtimeLabel).font(.caption).foregroundStyle(.secondary)
            Button(TahoeStrings.ui("View Diagnostics")) { TahoeReleaseInfo.showDiagnostics() }.buttonStyle(TahoeControlStyle())
            TahoePerformanceCaptureControl()
            Link("Download SideOS Releases", destination: TahoeReleaseInfo.releasesURL).buttonStyle(TahoeControlStyle())
            Text("Download an unsigned release and sign it with your own trusted tool. Opening Releases does not start a build.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity)
    }
}

struct TahoeSettingsToolbar: View {
    @ObservedObject var workspace: TahoeWorkspace
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                TahoeToolbarButton(symbol: "chevron.left", label: "Previous settings page", action: workspace.settingsBack).disabled(workspace.settingsBackStack.isEmpty)
                TahoeToolbarButton(symbol: "chevron.right", label: "Next settings page", action: workspace.settingsForward).disabled(workspace.settingsForwardStack.isEmpty)
            }
            Text(workspace.settingsSection).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 12)
            TahoeHelpButton(title: "Desktop Settings", message: "Change appearance, the Dock, browser defaults and window restoration. Only controls supported by this iPad desktop are shown.").padding(.trailing, 12)
        }.tahoeGlassGroup()
    }
}

