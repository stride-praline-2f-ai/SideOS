import SwiftUI

@MainActor
final class TahoeGuestSession: ObservableObject {
    let relativeBundlePath: String
    let dataUUID: String
    var lifecycleChanged: (() -> Void)?
    let launchID = UUID()
    @Published private var launchState = TahoeGuestLaunchState()
    var message: String? { launchState.message }
    var pid: Int32 { launchState.pid }
    var terminated: Bool { launchState.terminated }
    private(set) var initialViewport = CGSize.zero
    private(set) var wirelessPresentation = false
    private var exitReport: Task<Void, Never>?
    private(set) var controller: AppSceneViewController?
    private var viewport: UIViewController?
    private var callbacks: [(NSNumber?, Error?) -> Void] = []
    private var result: Result<Int32, Error>?
    private var watchdog: Task<Void, Never>?
    private var watchdogStarted: TimeInterval?
    private var watchdogRemaining: TimeInterval = 45
    private var active = true
    private let proxy = TahoeGuestDelegate()

    init(relativeBundlePath: String, dataUUID: String, completion: ((NSNumber?, Error?) -> Void)?) {
        self.relativeBundlePath = relativeBundlePath
        self.dataUUID = dataUUID
        if let completion { callbacks.append(completion) }
        proxy.session = self
    }

    func makeViewport(size: CGSize, wireless: Bool, onInteraction: @escaping () -> Void) -> UIViewController {
        if TahoeGuestLaunchState.validViewport(size) { initialViewport = size }
        wirelessPresentation = wireless
        // A display transfer mounts a new SwiftUI representable. Reparent the
        // existing guest controller into a fresh wrapper, never hand one wrapper
        // to two representables or restart its LiveProcess.
        (viewport as? TahoeGuestViewportController)?.detachGuest()
        let viewport = TahoeGuestViewportController(guest: makeController(), initialSize: initialViewport)
        viewport.onInteraction = onInteraction
        controller?.tahoeDisplayOrientationOverride = wireless ? (size.width > size.height ? .landscapeLeft : .portrait) : .unknown
        viewport.layoutChanged = { [weak self] in
            guard let self, self.pid > 0, !self.terminated, let controller = self.controller else { return }
            self.proxy.appSceneVCWillActivateScene(controller)
        }
        self.viewport = viewport
        return viewport
    }
    func makeController() -> UIViewController {
        if let controller { return controller }
        guard !terminated else { return UIViewController() }
        controller = AppSceneViewController(bundleId: relativeBundlePath, dataUUID: dataUUID, delegate: proxy)
        if let controller {
            if TahoeGuestLaunchState.validViewport(initialViewport) { controller.view.frame = CGRect(origin: .zero, size: initialViewport) }
            armWatchdog(); return controller
        }
        fail("Unable to create the guest presentation. Check LiveProcess and the installed entitlements.")
        return UIViewController()
    }
    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if !active {
            if let watchdogStarted { watchdogRemaining = max(0, watchdogRemaining - (ProcessInfo.processInfo.systemUptime - watchdogStarted)) }
            watchdog?.cancel(); watchdog = nil; watchdogStarted = nil
        } else if result == nil && controller != nil { armWatchdog() }
    }
    private func armWatchdog() {
        guard active, result == nil else { return }
        watchdog?.cancel(); watchdogStarted = ProcessInfo.processInfo.systemUptime
        let remaining = watchdogRemaining
        watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard let self, self.active, self.result == nil else { return }
            self.fail("The guest did not return a PID within 45 seconds of foreground time.")
            self.controller?.terminate()
        }
    }

    func addCompletion(_ completion: ((NSNumber?, Error?) -> Void)?) {
        guard let completion else { return }
        if let result { deliver(result, to: completion) }
        else { callbacks.append(completion) }
    }

    fileprivate func initialized(_ vc: AppSceneViewController?, error: Error?) {
        // Upstream cancellation calls cleanup/exit before delivering its error.
        // Accept that error unless the user explicitly closed this launch.
        guard launchState.initialized(pid: vc?.pid ?? 0, error: error?.localizedDescription) else { vc?.terminate(); return }
        exitReport?.cancel(); exitReport = nil
        if let error { settle(.failure(error)); vc?.terminate() }
        else if launchState.terminated { settle(.failure(Self.error(message ?? "LiveProcess did not start."))); vc?.terminate() }
        else { settle(.success(pid)) }
        lifecycleChanged?()
    }

    fileprivate func exited() {
        guard !launchState.closed else { return }
        if relativeBundlePath == TahoeInstallerRuntime.bundle { TahoeInstallerPickerServer.shared.invalidate() }
        launchState.exited()
        exitReport?.cancel()
        // Give a same-turn initialization error precedence over the generic exit.
        exitReport = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, !self.launchState.closed else { return }
            self.settle(.failure(Self.error(self.message ?? "The guest exited before launch completed.")))
        }
        lifecycleChanged?()
    }

    private func fail(_ message: String) {
        exitReport?.cancel(); exitReport = nil
        launchState.fail(message)
        settle(.failure(Self.error(message)))
        lifecycleChanged?()
    }

    func close() {
        if relativeBundlePath == TahoeInstallerRuntime.bundle { TahoeInstallerPickerServer.shared.invalidate() }
        exitReport?.cancel(); exitReport = nil
        launchState.close()
        settle(.failure(Self.error("Guest launch cancelled because its desktop window was closed.")))
        controller?.terminate()
        controller?.delegate = nil
        controller = nil
        viewport = nil
        lifecycleChanged = nil
    }

    private func settle(_ result: Result<Int32, Error>) {
        guard self.result == nil else { return }
        self.result = result
        watchdog?.cancel()
        watchdog = nil
        let callbacks = self.callbacks
        self.callbacks.removeAll()
        for callback in callbacks { deliver(result, to: callback) }
    }
    private func deliver(_ result: Result<Int32, Error>, to callback: (NSNumber?, Error?) -> Void) {
        switch result {
        case .success(let pid): callback(NSNumber(value: pid), nil)
        case .failure(let error): callback(nil, error)
        }
    }
    private static func error(_ message: String) -> NSError {
        NSError(domain: "TahoeDesktop.Guest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// The Objective-C controller retains its delegate. A weak back-reference avoids a session cycle.
@MainActor
// Upstream invokes this Objective-C UI delegate on the main thread. The
// imported protocol predates actor annotations; defer its isolation check.
private final class TahoeGuestDelegate: NSObject, @preconcurrency AppSceneViewControllerDelegate {
    weak var session: TahoeGuestSession?
    func appSceneVCAppDidExit(_ vc: AppSceneViewController!) {
        DispatchQueue.main.async { [weak self] in self?.session?.exited() }
    }
    func appSceneVC(_ vc: AppSceneViewController!, didInitializeWithError error: Error!) {
        DispatchQueue.main.async { [weak self] in self?.session?.initialized(vc, error: error) }
    }
    func appSceneVCWillActivateScene(_ vc: AppSceneViewController!) {
        vc.updateSettings { settings in
            guard let settings else { return }
            // Insets belong to our content rectangle, not the entire iPad screen.
            settings.peripheryInsets = .zero
            settings.safeAreaInsetsPortrait = .zero
            let measured = vc.view.bounds.size
            let size = TahoeGuestLaunchState.validViewport(measured) ? measured : self.session?.initialViewport ?? .zero
            guard TahoeGuestLaunchState.validViewport(size) else { return }
            let orientation: UIInterfaceOrientation
            if self.session?.wirelessPresentation == true { orientation = size.width > size.height ? .landscapeLeft : .portrait }
            else { orientation = vc.view.window?.windowScene?.effectiveGeometry.interfaceOrientation ??
                TahoeWorkspace.shared.hostWindow?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait }
            settings.deviceOrientation = self.session?.wirelessPresentation == true ? (orientation.isLandscape ? .landscapeRight : .portrait) : UIDevice.current.orientation
            settings.setInterfaceOrientation(orientation)
            settings.setFrame(CGRect(x: 0, y: 0, width: orientation.isLandscape ? size.height : size.width,
                                     height: orientation.isLandscape ? size.width : size.height))
        }
        // Match upstream's live-resize path; avoid repeated scene-frame updates
        // during every SwiftUI layout tick.
        vc.contentView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.view.setNeedsLayout()
    }
    func appSceneVC(_ vc: AppSceneViewController!, didUpdateFrom settings: UIMutableApplicationSceneSettings!,
                    transitionContext context: Any!, lifecycleActionType actionType: UInt32) {
        guard let settings else { return }
        settings.interruptionPolicy = 0
        vc.presenter?.scene.updateSettings(settings, withTransitionContext: context, completion: nil)
    }
}

struct TahoeGuestView: View {
    @ObservedObject var session: TahoeGuestSession
    let windowID: UUID
    @EnvironmentObject private var model: SharedModel
    var body: some View {
        GeometryReader { geometry in
            ZStack {
            if TahoeGuestLaunchState.validViewport(geometry.size) {
                TahoeGuestSurface(session: session, initialSize: geometry.size,
                    wireless: TahoeWorkspace.shared.state.windows.first(where: { $0.id == windowID })?.onWirelessDisplay == true, onInteraction: {
                    let workspace = TahoeWorkspace.shared
                    if workspace.overlay == nil && workspace.state.activeID != windowID { workspace.state.focusVisible(windowID) }
                }).id(session.launchID)
            }
            if session.pid == 0 && !session.terminated {
                VStack(spacing: 12) { ProgressView(); Text(TahoeStrings.ui("Opening application…")).font(.callout).foregroundStyle(.secondary) }
                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
            }
            if let message = session.message {
                VStack(spacing: 14) {
                    Text(message).font(.callout).textSelection(.enabled)
                    HStack {
                        if let app = model.apps.first(where: { $0.appInfo.relativeBundlePath == session.relativeBundlePath }) {
                            Button(TahoeStrings.ui("Relaunch")) {
                                let workspace = TahoeWorkspace.shared
                                if let id = workspace.state.windows.first(where: { $0.kind == .guest && $0.resourceID == session.dataUUID })?.id { workspace.close(id) }
                                Task { await workspace.launch(app) }
                            }.buttonStyle(TahoeControlStyle())
                        }
                        Button(TahoeStrings.ui("JIT / App Management")) { TahoeWorkspace.shared.showManagement = true }.buttonStyle(TahoeControlStyle())
                    }
                    Button(TahoeStrings.ui("Copy Error")) { UIPasteboard.general.string = message }.buttonStyle(TahoeControlStyle())
                }.padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
    }
    }
}

private struct TahoeGuestSurface: UIViewControllerRepresentable {
    let session: TahoeGuestSession
    let initialSize: CGSize
    let wireless: Bool
    let onInteraction: () -> Void
    func makeUIViewController(context: Context) -> UIViewController { session.makeViewport(size: initialSize, wireless: wireless, onInteraction: onInteraction) }
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        (vc as? TahoeGuestViewportController)?.onInteraction = onInteraction
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIViewController, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height, width.isFinite, height.isFinite else { return nil }
        return CGSize(width: max(0, width), height: max(0, height))
    }
    // Minimise/fullscreen only change modifiers; no termination in dismantle.
}

/// The guest receives exactly the content rectangle below our title bar.
/// Its private scene host must not determine the size of the SwiftUI window.
private final class TahoeGuestViewportController: UIViewController, UIGestureRecognizerDelegate {
    let guest: UIViewController
    let initialSize: CGSize
    var onInteraction: (() -> Void)?
    var layoutChanged: (() -> Void)?
    private var reportedPlacement = false
    init(guest: UIViewController, initialSize: CGSize) { self.guest = guest; self.initialSize = initialSize; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { return nil }
    override func loadView() { view = UIView(frame: CGRect(origin: .zero, size: initialSize)) }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        addChild(guest); view.addSubview(guest.view); guest.didMove(toParent: self)
        guest.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        guest.view.frame = view.bounds
        // Observe touches at the UIKit ancestor of the remote scene. SwiftUI's
        // TapGesture does not reliably see touches consumed by hosted apps.
        // Reject recognition immediately so app taps, scrolls and long presses
        // are never delayed or cancelled. Focus happens on touch-down, before
        // an app action can open, close or minimise another window.
        let observer = UITapGestureRecognizer()
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.delegate = self
        view.addGestureRecognizer(observer)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        onInteraction?()
        return false
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard guest.parent === self else { return }
        if guest.view.frame != view.bounds { guest.view.frame = view.bounds; guest.view.setNeedsLayout() }
        if !reportedPlacement && view.window != nil { reportedPlacement = true; layoutChanged?() }
    }
    func detachGuest() {
        guard guest.parent === self else { return }
        guest.willMove(toParent: nil); guest.view.removeFromSuperview(); guest.removeFromParent()
        onInteraction = nil
        layoutChanged = nil
    }
}
