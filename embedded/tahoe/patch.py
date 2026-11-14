"""Opt-in desktop adaptation, applied only after the existing embedded adaptation."""
import shutil
import plistlib
from pathlib import Path


def patch(root, replace):
    here = Path(__file__).resolve().parent
    destination = root / "LiveContainerSwiftUI/TahoeDesktop"
    destination.mkdir(exist_ok=False)
    for source in here.glob("*.swift"):
        if source.name.endswith("Tests.swift"):
            continue
        shutil.copyfile(source, destination / source.name)
    for shader in here.glob("*.metal"):
        shutil.copyfile(shader, destination / shader.name)
    shutil.copytree(here / "Notices", destination / "Notices")
    shutil.copytree(here / "Assets.xcassets", destination / "Assets.xcassets")
    shutil.copytree(here / "Localization", destination / "Localization")
    app_icon = root / "Resources/Assets.xcassets/AppIcon.appiconset"
    if app_icon.exists(): shutil.rmtree(app_icon)
    shutil.copytree(here / "AppIcon.appiconset", app_icon)
    info = root / "LiveContainer/Info.plist"
    data = plistlib.loads(info.read_bytes())
    data["CFBundleDisplayName"] = "SideOS"
    data["NSLocalNetworkUsageDescription"] = "Connect SideOS devices on your local network for an encrypted extended display."
    data["NSBonjourServices"] = sorted(set(data.get("NSBonjourServices", [])) | {"_sideos-screen._tcp"})
    # Upstream advertises LaunchScreen without shipping that storyboard and
    # retains launch images with old phone dimensions. Use the iOS 14+ adaptive
    # launch screen, so a new display is not treated as a legacy phone canvas.
    for key in ("UILaunchStoryboardName", "UILaunchImageFile", "UILaunchImages"):
        data.pop(key, None)
    data["UILaunchScreen"] = {}
    data["UIDeviceFamily"] = [1, 2]
    orientations = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
    data["UISupportedInterfaceOrientations"] = orientations
    data["UISupportedInterfaceOrientations~ipad"] = orientations
    data["CFBundleLocalizations"] = sorted(set(data.get("CFBundleLocalizations", [])) | {"en", "es", "ar"})
    data["NSCameraUsageDescription"] = "Allow camera access for websites and hosted apps when requested."
    data["NSMicrophoneUsageDescription"] = "Allow microphone access for websites and hosted apps when requested."
    data.setdefault("NSAppTransportSecurity", {})["NSAllowsArbitraryLoadsInWebContent"] = True
    info.write_bytes(plistlib.dumps(data, sort_keys=False))

    # Keep startup, alerts and deep-link handling on the original root. Host
    # only its tab content in one retained controller inside a desktop window.
    tabs = root / "LiveContainerSwiftUI/Views/LCTabView.swift"
    replace(tabs, "struct LCTabView: View {", "struct LCTabView: View {\n    @ObservedObject private var tahoeWorkspace = TahoeWorkspace.shared\n    @StateObject private var tahoeManagementHost = TahoeManagementHost()", 1)
    source = tabs.read_text()
    begin = source.index("        TabView(selection: $sharedModel.selectedTab) {")
    cursor = source.index("{", begin) + 1
    depth = 1
    while depth:
        if source[cursor] == "{": depth += 1
        elif source[cursor] == "}": depth -= 1
        cursor += 1
    tab_content = source[begin:cursor]
    desktop = ("        TahoeDesktopView()\n"
               "            .environment(\\.tahoeManagementHost, tahoeManagementHost)\n"
               "            .background {\n"
               "                TahoeManagementBootstrap(host: tahoeManagementHost, content: AnyView(tahoeManagementTabs\n"
               "                    .environmentObject(sharedModel).environmentObject(sceneDelegate).environmentObject(downloadHelper)\n"
               "                    .environment(\\.scenePhase, scenePhase)))\n"
               "                    .frame(width: 1, height: 1).opacity(0).allowsHitTesting(false).accessibilityHidden(true)\n"
               "            }")
    source = source[:begin] + desktop + source[cursor:]
    anchor = "    func dispatchURL(url: URL) {"
    assert source.count(anchor) == 1
    source = source.replace(anchor, "    private var tahoeManagementTabs: some View {\n" + tab_content + "\n    }\n\n" + anchor)
    tabs.write_text(source)
    replace(tabs, "        .downloadAlert(helper: downloadHelper)",
            "        .alert(\"Desktop\", isPresented: Binding(get: { tahoeWorkspace.error != nil }, set: { if !$0 { tahoeWorkspace.error = nil } })) {\n"
            "            Button(\"OK\") { tahoeWorkspace.error = nil }\n"
            "        } message: { Text(tahoeWorkspace.error ?? \"\") }\n"
            "        .downloadAlert(helper: downloadHelper)", 1)
    replace(tabs, "            dispatchURL(url: url)",
            "            tahoeWorkspace.showManagement = true\n            dispatchURL(url: url)", 1)

    utils = root / "LiveContainerSwiftUI/Utilities/LCUtils.m"
    replace(utils, "    dispatch_async(dispatch_get_main_queue(), ^{\n        if (@available(iOS 16.1, *)) {",
            "    dispatch_async(dispatch_get_main_queue(), ^{\n"
            "        if ([TahoeGuestRouter openWithDisplayName:displayName bundleID:bundleId dataUUID:dataUUID completion:completionHandler]) return;\n"
            "        if (@available(iOS 16.1, *)) {", 1)
    model = root / "LiveContainerSwiftUI/Models/LCAppModel.swift"
    replace(model,
            "    private func bringExistingMultitaskWindowIfNeeded(dataUUID: String, urlScheme: String?) async -> Bool {",
            "    private func bringExistingMultitaskWindowIfNeeded(dataUUID: String, urlScheme: String?) async -> Bool {\n"
            "        if await MainActor.run(body: { TahoeWorkspace.shared.focusGuest(dataUUID: dataUUID, url: urlScheme) }) { return true }", 1)

    # A close during beginExtensionRequest must kill the eventual child before
    # scene creation, even if no PID existed at the time of the close request.
    scene = root / "MultitaskSupport/AppSceneViewController.m"
    replace(root / "MultitaskSupport/AppSceneViewController.h",
            "@property(nonatomic) CGFloat scaleRatio;",
            "@property(nonatomic) CGFloat scaleRatio;\n@property(nonatomic) UIInterfaceOrientation tahoeDisplayOrientationOverride;", 1)
    replace(scene,
            "settings.interfaceOrientation = self.view.window.windowScene.interfaceOrientation;",
            "settings.interfaceOrientation = self.tahoeDisplayOrientationOverride != UIInterfaceOrientationUnknown ? self.tahoeDisplayOrientationOverride : self.view.window.windowScene.interfaceOrientation;", 1)
    replace(scene, "@property int resizeDebounceToken;",
            "@property int resizeDebounceToken;\n@property(atomic) BOOL tahoeTerminationRequested;", 1)
    replace(scene, "- (void)terminate {\n    if(self.isAppRunning) {",
            "- (void)terminate {\n    self.tahoeTerminationRequested = YES;\n    if(self.isAppRunning) {", 1)
    replace(scene, "            self.pid = [self.extension pidForRequestIdentifier:self.identifier];",
            "            self.pid = [self.extension pidForRequestIdentifier:self.identifier];\n"
            "            if (self.tahoeTerminationRequested) {\n"
            "                [self terminate];\n"
            "                [self appTerminationCleanUp];\n"
            "                return;\n"
            "            }", 1)
    replace(scene, "                [self setUpAppPresenter];",
            "                if (!self.tahoeTerminationRequested) [self setUpAppPresenter];", 1)
    patch_installer_window(root, replace)
    (root / ".tahoe-adapted").write_text("desktop-v2-private\n")


def patch_installer_window(root, replace):
    bootstrap = root / "LiveContainer/LCBootstrap.m"
    replace(bootstrap,
            '    if(isSideStore) {\n'
            '        tweakLoaderLoaded = true;\n'
            '        dlopen([lcMainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/TweakLoader.dylib"].UTF8String, RTLD_LAZY|RTLD_GLOBAL);\n'
            '    }',
            (Path(__file__).resolve().parent / 'InstallerFilesRuntime.m.inc').read_text().rstrip(), 1)
    utils = root / "LiveContainerSwiftUI/Utilities/LCUtilsExtensions.swift"
    replace(utils,
            '    static func openSideStore(delegate: LCAppModelDelegate? = nil, urlStr: String? = nil) {',
            '    static func openSideStore(delegate: LCAppModelDelegate? = nil, urlStr: String? = nil) {\n'
            '        if urlStr == nil {\n'
            '            Task { @MainActor in TahoeWorkspace.shared.openInstaller() }\n'
            '            return\n'
            '        }', 1)
    scene = root / "MultitaskSupport/AppSceneViewController.m"
    replace(scene,
            '    self.isNativeWindow = [NSUserDefaults.lcSharedDefaults integerForKey:@"LCMultitaskMode" ] == 1;',
            '    self.isNativeWindow = ![bundleId isEqualToString:@"builtinSideStore"] && [NSUserDefaults.lcSharedDefaults integerForKey:@"LCMultitaskMode" ] == 1;', 1)
    replace(scene,
            '    if ([NSUserDefaults.standardUserDefaults boolForKey:@"LCSharePrivateDataWithLiveProcess"]) {',
            '    if ([bundleId isEqualToString:@"builtinSideStore"]) {\n'
            '        NSURL *installerHome = [docURL URLByAppendingPathComponent:@"SideInstaller" isDirectory:YES];\n'
            '        NSError *installerError = nil;\n'
            '        [[NSFileManager defaultManager] createDirectoryAtURL:installerHome withIntermediateDirectories:YES attributes:nil error:&installerError];\n'
            '        NSData *installerBookmark = installerError ? nil : [installerHome bookmarkDataWithOptions:(1<<11) includingResourceValuesForKeys:nil relativeToURL:nil error:&installerError];\n'
            '        if (!installerBookmark) {\n'
            '            [delegate appSceneVC:self didInitializeWithError:installerError ?: [NSError errorWithDomain:@"SideOS.Installer" code:1 userInfo:@{NSLocalizedDescriptionKey:@"SideInstaller could not open its data folder."}]];\n'
            '            return nil;\n'
            '        }\n'
            '        [bookmarks addObject:installerBookmark];\n'
            '    } else if ([NSUserDefaults.standardUserDefaults boolForKey:@"LCSharePrivateDataWithLiveProcess"]) {', 1)
    # The host owns Files UI. The guest receives only its private mailbox
    # channel, alongside the bookmark for the existing installer container.
    replace(scene, '        [bookmarks addObject:installerBookmark];',
            '        [bookmarks addObject:installerBookmark];\n'
            '        NSString *pickerChannel = [TahoeInstallerPickerServer prepareChannel];\n'
            '        if (pickerChannel) userInfo[@"sideosIPAPickerChannel"] = pickerChannel;', 1)
    # Background refresh supplies an XPC endpoint; the interactive desktop
    # window needs no refresh server. Keep the existing transport unchanged.
    process = root / "LiveProcess/main.m"
    replace(process, '        NSXPCListenerEndpoint* endpoint = appInfo[@"endpoint"];',
            '        NSString *pickerChannel = appInfo[@"sideosIPAPickerChannel"];\n'
            '        if (pickerChannel.length) setenv("SI_HOST_IPA_PICKER_CHANNEL", pickerChannel.UTF8String, 1);\n'
            '        NSXPCListenerEndpoint* endpoint = appInfo[@"endpoint"];', 1)
    replace(process,
            '        NSXPCConnection* connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];',
            '        if (endpoint) {\n'
            '        NSXPCConnection* connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];', 1)
    replace(process,
            '        LiveProcessSideStoreHandler.shared.connection = connection;',
            '        LiveProcessSideStoreHandler.shared.connection = connection;\n'
            '        }', 1)
    client = root / "SideStoreSupport/XPCClient.m"
    replace(client, '    installSideStoreNotificationHooks();',
            '    if (!handler.connection) return; // Interactive window uses local notifications.\n'
            '    installSideStoreNotificationHooks();', 1)

