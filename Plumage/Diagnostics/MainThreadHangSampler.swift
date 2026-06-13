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

    private let timerQueue = DispatchQueue(
        label: "com.plumage.hang-sampler", qos: .userInteractive)
    private let intervalMs: Int
    private let thresholdMs: Double
    private let markerURL: URL?
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
        self.thresholdMs = Double(env["PLUMAGE_HANG_THRESHOLD_MS"] ?? "") ?? 100
        if let path = env["PLUMAGE_HANG_MARKER"] {
            self.markerURL = URL(filePath: path)
        } else if Self.isEnabled {
            self.markerURL = URL(filePath: "/tmp/plumage-hangsampler.json")
        } else {
            self.markerURL = nil
        }
    }

    func startIfEnabled() {
        guard Self.isEnabled else { return }
        timerQueue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: timerQueue)
            source.schedule(
                deadline: .now() + .milliseconds(intervalMs), repeating: .milliseconds(intervalMs))
            source.setEventHandler { [self] in probe() }
            timer = source
            writeMarker(lock.withLock { $0 })
            log.notice(
                "MainThreadHangSampler started (interval \(self.intervalMs)ms, threshold \(Int(self.thresholdMs))ms)"
            )
            source.resume()
        }
    }

    var stats: HangStats { lock.withLock { $0 } }

    private func probe() {
        if FileManager.default.fileExists(atPath: "/tmp/plumage-hang-reset") {
            try? FileManager.default.removeItem(atPath: "/tmp/plumage-hang-reset")
            lock.withLock { $0 = HangStats() }
            writeMarker(lock.withLock { $0 })
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
