import SwiftUI
import Darwin

struct TahoeDisplaySnapshot: Equatable {
    var size = CGSize(width: 1024, height: 768)
    var nativePixels = CGSize.zero
    var screenPoints = CGSize.zero
    var scenePoints = CGSize.zero
    var scale: CGFloat = 1
    var safe = TahoeViewportPolicy.Insets()
    var phone = false
}

@MainActor final class TahoeDisplayMetrics: ObservableObject {
    static let shared = TahoeDisplayMetrics()
    @Published private(set) var snapshot = TahoeDisplaySnapshot()
    private static let hardware: String = {
        var length = 0
        guard sysctlbyname("hw.machine", nil, &length, nil, 0) == 0, length > 0, length < 256 else { return "" }
        var bytes = [CChar](repeating: 0, count: length)
        let result = bytes.withUnsafeMutableBytes { sysctlbyname("hw.machine", $0.baseAddress, &length, nil, 0) }
        guard result == 0 else { return "" }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }()
    func update(window: UIWindow) {
        guard let screen = window.windowScene?.screen, window.bounds.width > 0, window.bounds.height > 0 else { return }
        let safe = window.safeAreaInsets
        let value = TahoeDisplaySnapshot(size: window.bounds.size, nativePixels: screen.nativeBounds.size,
            screenPoints: screen.bounds.size, scenePoints: window.windowScene?.coordinateSpace.bounds.size ?? .zero, scale: screen.scale,
            safe: .init(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right),
            phone: TahoeViewportPolicy.isPhone(idiom: UIDevice.current.userInterfaceIdiom == .phone,
                model: UIDevice.current.model, hardware: Self.hardware))
        if snapshot != value { snapshot = value }
    }
    func layout(for size: CGSize) -> TahoeViewportPolicy.Layout {
        TahoeViewportPolicy.layout(size: size, safe: snapshot.safe, phone: snapshot.phone,
                                   mode: TahoePreferences.shared.value.displayLayoutMode)
    }
    var current: TahoeViewportPolicy.Layout { layout(for: snapshot.size) }
    var diagnostics: String {
        let v = current
        return "\(v.label)\nWindow: \(Int(snapshot.size.width)) × \(Int(snapshot.size.height)) pt\nUsable: \(Int(v.viewport.width)) × \(Int(v.viewport.height)) pt\nScene: \(Int(snapshot.scenePoints.width)) × \(Int(snapshot.scenePoints.height)) pt\nScreen: \(Int(snapshot.screenPoints.width)) × \(Int(snapshot.screenPoints.height)) pt\nDisplay: \(Int(snapshot.nativePixels.width)) × \(Int(snapshot.nativePixels.height)) px · \(String(format: "%.2f", snapshot.scale))× scale"
    }
}
