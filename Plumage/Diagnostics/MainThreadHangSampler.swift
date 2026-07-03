import Foundation
import os

// Pure seam so the aggregation is unit-tested without a flaky timing test.
nonisolated struct HangStats: Sendable, Equatable {
    var maxStallMs: Double = 0
    var stallCount = 0
    var sampleCount = 0

    mutating func record(stallMs: Double, thresholdMs: Double) -> Bool {
        sampleCount += 1
        let isNewMax = stallMs > maxStallMs
        if isNewMax { maxStallMs = stallMs }
        if stallMs >= thresholdMs { stallCount += 1 }
        return isNewMax
    }
}

// Inert unless PLUMAGE_HANG_SAMPLER or the /tmp/plumage-hang-sampler.on sentinel is set.
// @unchecked Sendable: `timer` confined to timerQueue, stats guarded by `lock`.
nonisolated final class MainThreadHangSampler: @unchecked Sendable {
    static let shared = MainThreadHangSampler()

    private static let resetPath = "/tmp/plumage-hang-reset"

    // A 50 ms diagnostic timer has no reason to pin CPU P-states high.
    private let timerQueue = DispatchQueue(
        label: "com.plumage.hang-sampler", qos: .utility)
    private let intervalMs: Int
    private let thresholdMs: Double
    private let markerURL: URL?
    // Throttle the control-file checks (reset / sentinel) to ~1 Hz instead of
    // stat-ing on every probe.
    private let controlEvery: Int
    private var controlTick = 0
    private let signposter = OSSignposter(subsystem: "com.plumage", category: "MainThreadHang")
    private let log = Logger(subsystem: "com.plumage", category: "MainThreadHang")
    private let lock = OSAllocatedUnfairLock(initialState: HangStats())
    private var timer: DispatchSourceTimer?

    static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["PLUMAGE_HANG_SAMPLER"] != nil { return true }
        return FileManager.default.fileExists(atPath: "/tmp/plumage-hang-sampler.on")
    }

    private init() {
        let env = ProcessInfo.processInfo.environment
        let intervalMs = Int(env["PLUMAGE_HANG_INTERVAL_MS"] ?? "") ?? 50
        self.intervalMs = intervalMs
        self.controlEvery = max(1, 1000 / intervalMs)
        self.thresholdMs = Double(env["PLUMAGE_HANG_THRESHOLD_MS"] ?? "") ?? 100
        if let path = env["PLUMAGE_HANG_MARKER"], Self.isSafeMarkerPath(path) {
            self.markerURL = URL(filePath: path)
        } else if Self.isEnabled {
            self.markerURL = URL(filePath: "/tmp/plumage-hangsampler.json")
        } else {
            self.markerURL = nil
        }
    }

    // Developer-only knob; still refuse a path outside /tmp or $HOME so a stray
    // env var can't aim the marker writer at an arbitrary location.
    private static func isSafeMarkerPath(_ path: String) -> Bool {
        path.hasPrefix("/tmp/") || path.hasPrefix(NSHomeDirectory() + "/")
    }

    func startIfEnabled() {
        guard Self.isEnabled else { return }
        timerQueue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: timerQueue)
            source.schedule(
                deadline: .now() + .milliseconds(intervalMs),
                repeating: .milliseconds(intervalMs),
                leeway: .milliseconds(max(1, intervalMs / 10)))
            source.setEventHandler { [self] in probe() }
            timer = source
            writeMarker(lock.withLock { $0 })
            log.notice(
                "MainThreadHangSampler started (interval \(self.intervalMs)ms, threshold \(Int(self.thresholdMs))ms)"
            )
            source.resume()
        }
    }

    private func cancelTimerOnQueue() {
        timer?.cancel()
        timer = nil
    }

    private func probe() {
        controlTick += 1
        if controlTick >= controlEvery {
            controlTick = 0
            // Sentinel removed mid-run → stop instead of sampling forever. Env
            // mode stays on (isEnabled can't flip), matching its explicit intent.
            guard Self.isEnabled else {
                cancelTimerOnQueue()
                log.notice("MainThreadHangSampler stopped (sentinel gone)")
                return
            }
            if FileManager.default.fileExists(atPath: Self.resetPath) {
                try? FileManager.default.removeItem(atPath: Self.resetPath)
                let cleared = lock.withLock { stats -> HangStats in
                    stats = HangStats()
                    return stats
                }
                writeMarker(cleared)
            }
        }
        let scheduled = DispatchTime.now()
        DispatchQueue.main.async { [self] in
            let stallNs = DispatchTime.now().uptimeNanoseconds &- scheduled.uptimeNanoseconds
            timerQueue.async { [self] in record(stallMs: Double(stallNs) / 1_000_000) }
        }
    }

    private func record(stallMs: Double) {
        let (isNewMax, snapshot) = lock.withLock { stats -> (Bool, HangStats) in
            let isNewMax = stats.record(stallMs: stallMs, thresholdMs: thresholdMs)
            return (isNewMax, stats)
        }
        if stallMs >= thresholdMs {
            signposter.emitEvent("stall", "\(Int(stallMs))ms")
            log.notice("main-thread stall \(Int(stallMs))ms (stalls \(snapshot.stallCount))")
        }
        if isNewMax { writeMarker(snapshot) }
    }

    private func writeMarker(_ stats: HangStats) {
        guard let markerURL else { return }
        let json = """
            {"maxStallMs": \(stats.maxStallMs), "stallCount": \(stats.stallCount), \
            "sampleCount": \(stats.sampleCount)}
            """
        try? json.write(to: markerURL, atomically: true, encoding: .utf8)
    }
}
