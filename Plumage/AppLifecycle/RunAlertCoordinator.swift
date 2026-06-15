import AppKit
import Foundation
import os

// Requests dock attention only while not frontmost, for a hook signal that maps
// to a live run.
@MainActor
@Observable
final class RunAlertCoordinator {
    private static let logger = Logger(subsystem: "com.plumage", category: "RunAlertCoordinator")

    private let signalURL: URL
    private let isFrontmost: @MainActor () -> Bool
    private let hasLiveRun: @Sendable (URL) -> Bool
    private let requestAttention: @MainActor () -> Void

    private var watcher: FSEventSource?
    private var readOffset: UInt64 = 0

    init(
        signalURL: URL = AgentNotificationHook.signalFileURL(),
        isFrontmost: @escaping @MainActor () -> Bool = { NSApp.isActive },
        hasLiveRun: @escaping @Sendable (URL) -> Bool = {
            ImplementRunScanner.liveImplementRun(in: $0) != nil
        },
        requestAttention: @escaping @MainActor () -> Void = {
            // Informational (one bounce), not critical — a run signal is routine,
            // not an exceptional condition warranting a persistent bounce.
            NSApp.requestUserAttention(.informationalRequest)
        }
    ) {
        self.signalURL = signalURL
        self.isFrontmost = isFrontmost
        self.hasLiveRun = hasLiveRun
        self.requestAttention = requestAttention
    }

    func start() {
        let dir = signalURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Self.logger.error(
                "signal dir unavailable, dock attention off: \(error.localizedDescription, privacy: .public)"
            )
        }
        // Start past the current end so a relaunch never bounces for stale lines.
        if let file = try? FileHandle(forReadingFrom: signalURL) {
            readOffset = (try? file.seekToEnd()) ?? 0
            try? file.close()
        }
        let source = FSEventSource(directory: dir) { [weak self] in
            Task { @MainActor in self?.processNewSignals() }
        }
        source.start()
        watcher = source
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }

    nonisolated static func shouldAlert(isFrontmost: Bool, hasLiveRun: Bool) -> Bool {
        hasLiveRun && !isFrontmost
    }

    @discardableResult
    func handle(_ signal: AgentNotificationSignal) -> Bool {
        let live = hasLiveRun(URL(filePath: signal.cwd))
        guard Self.shouldAlert(isFrontmost: isFrontmost(), hasLiveRun: live) else { return false }
        requestAttention()
        return true
    }

    private func processNewSignals() {
        guard let file = try? FileHandle(forReadingFrom: signalURL) else { return }
        defer { try? file.close() }
        try? file.seek(toOffset: readOffset)
        guard let data = try? file.readToEnd(), !data.isEmpty else { return }
        readOffset += UInt64(data.count)
        guard let text = String(data: data, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        for line in text.split(whereSeparator: \.isNewline) {
            if let signal = AgentNotificationSignal.parse(line: String(line), decoder: decoder) {
                handle(signal)
            }
        }
    }
}
