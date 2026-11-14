import SwiftUI
import QuartzCore
import Darwin

/// Opt-in device evidence. Callback cadence measures the main run loop, not
/// GPU-rendered FPS. Host footprint does not include separate WebKit processes.
@MainActor final class TahoePerformanceCapture: NSObject, ObservableObject {
    static let shared = TahoePerformanceCapture()
    @Published private(set) var capturing = false
    @Published private(set) var report = "No device capture recorded."
    private var link: CADisplayLink?
    private var stopTask: Task<Void, Never>?
    private var previous: CFTimeInterval?
    private var intervals: [Double] = []
    private var hostPeak: UInt64 = 0
    private var gaps = 0
    private var ticks = 0
    func start() {
        guard !capturing else { return }
        intervals = []; previous = nil; gaps = 0; ticks = 0; hostPeak = footprint(); capturing = true
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common); self.link = link
        stopTask = Task { @MainActor [weak self] in do { try await Task.sleep(for: .seconds(20)) } catch { return }; self?.stop() }
    }
    func stop() {
        guard capturing else { return }
        link?.invalidate(); link = nil; stopTask?.cancel(); stopTask = nil; capturing = false
        let sorted = intervals.sorted()
        func percentile(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] * 1000 }
        report = """
        Device capture: \(sorted.count) foreground main-loop intervals
        Median callback interval: \(String(format: "%.1f", percentile(0.5))) ms
        P95 callback interval: \(String(format: "%.1f", percentile(0.95))) ms
        Callback gaps > 1.5× expected interval: \(gaps)
        Peak host footprint: \(hostPeak == 0 ? "Unavailable" : String(hostPeak / 1_048_576) + " MiB")
        These are main-loop callback timings, not rendered-frame FPS. Host memory excludes WebKit subprocesses. Use an Instruments trace for attribution.
        """
    }
    @objc private func tick(_ link: CADisplayLink) {
        guard UIApplication.shared.applicationState == .active else { previous = nil; return }
        if let previous {
            let interval = link.timestamp - previous
            if interval > 0 && intervals.count < 4096 {
                intervals.append(interval)
                if interval > max(0.001, link.targetTimestamp - link.timestamp) * 1.5 { gaps += 1 }
            }
        }
        previous = link.timestamp; ticks += 1
        if ticks % 60 == 0 { hostPeak = max(hostPeak, footprint()) }
    }
    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
}
struct TahoePerformanceCaptureControl: View {
    @ObservedObject private var capture = TahoePerformanceCapture.shared
    var body: some View {
        VStack(spacing: 8) {
            Button(capture.capturing ? "Stop Performance Capture" : "Capture 20 Seconds of Performance") { if capture.capturing { capture.stop() } else { capture.start() } }.buttonStyle(TahoeControlStyle())
            Text(capture.capturing ? "Reproduce the interaction, then open Diagnostics for the result." : "Optional device measurement. Diagnostics includes the most recent result.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
