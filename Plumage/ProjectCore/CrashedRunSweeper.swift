import Foundation
import os

nonisolated struct RunFileIdentity: Equatable, Sendable {
    let fileNumber: UInt64
    let modificationDate: Date
}

nonisolated protocol RunSweepFileOps: Sendable {
    func read(at url: URL) throws -> Data
    func identity(at url: URL) throws -> RunFileIdentity
    func createDirectory(at url: URL) throws
    func writeAtomic(_ data: Data, to url: URL) throws
    func removeIfUnchanged(at url: URL, identity: RunFileIdentity) throws -> Bool
    func remove(at url: URL) throws
}

nonisolated struct ProductionRunSweepFileOps: RunSweepFileOps {
    func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func identity(at url: URL) throws -> RunFileIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard
            let fileNumber = attributes[.systemFileNumber] as? UInt64,
            let modificationDate = attributes[.modificationDate] as? Date
        else { throw CocoaError(.fileReadUnknown) }
        return RunFileIdentity(fileNumber: fileNumber, modificationDate: modificationDate)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func writeAtomic(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func removeIfUnchanged(at url: URL, identity: RunFileIdentity) throws -> Bool {
        guard try self.identity(at: url) == identity else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }

    func remove(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

nonisolated enum CrashedRunSweeper {
    static let gracePeriod: TimeInterval = 120

    private static let logger = Logger(subsystem: "com.plumage", category: "CrashedRunSweeper")

    static func outcome(for state: RunState) -> String {
        if let phase = state.phase, phase.hasPrefix("failed") { return phase }
        return "crashed"
    }

    static func isEligible(
        _ snapshot: RunStateSnapshot,
        queuedSlugs: Set<String>,
        now: Date,
        grace: TimeInterval = gracePeriod
    ) -> Bool {
        guard !snapshot.isAgentAlive else { return false }
        guard !queuedSlugs.contains(snapshot.slug) else { return false }
        // A run-state without timestamps cannot be a fresh resume — those
        // always write lastProgressAt — so it sweeps immediately.
        guard let reference = snapshot.state.lastProgressAt ?? snapshot.state.startedAt else {
            return true
        }
        return now.timeIntervalSince(reference) > grace
    }

    @discardableResult
    static func sweep(
        snapshots: [RunStateSnapshot],
        now: Date = .now,
        grace: TimeInterval = gracePeriod,
        fileOps: some RunSweepFileOps = ProductionRunSweepFileOps(),
        queuedSlugs: (URL) -> Set<String> = { root in
            Set(ImplementRunScanner.queuedImplementRuns(in: root).map(\.issue))
        }
    ) -> Int {
        var swept = 0
        var queuedByRoot: [String: Set<String>] = [:]
        for snapshot in snapshots {
            let rootKey = snapshot.checkoutRoot.standardizedFileURL.path
            let queued = queuedByRoot[rootKey] ?? queuedSlugs(snapshot.checkoutRoot)
            queuedByRoot[rootKey] = queued
            guard isEligible(snapshot, queuedSlugs: queued, now: now, grace: grace) else {
                continue
            }
            if sweepOne(snapshot, now: now, grace: grace, queued: queued, fileOps: fileOps) {
                swept += 1
            }
        }
        return swept
    }

    private static func sweepOne(
        _ snapshot: RunStateSnapshot,
        now: Date,
        grace: TimeInterval,
        queued: Set<String>,
        fileOps: some RunSweepFileOps
    ) -> Bool {
        guard let bundle = try? BundleResolver.findBundle(in: snapshot.checkoutRoot) else {
            return false
        }
        let runStateURL = bundle.appendingPathComponent("runs/\(snapshot.slug).json")
        guard
            let identity = try? fileOps.identity(at: runStateURL),
            let data = try? fileOps.read(at: runStateURL),
            let fresh = try? RunStateReader.decode(data),
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return false }

        // Re-check on the fresh read: a resume may have rewritten the file
        // (live pid, new timestamps) since the snapshot was taken.
        let freshSnapshot = RunStateSnapshot(
            checkoutRoot: snapshot.checkoutRoot,
            slug: snapshot.slug,
            state: fresh,
            isAgentAlive: isAlive(pid: fresh.agentPid)
        )
        guard isEligible(freshSnapshot, queuedSlugs: queued, now: now, grace: grace) else {
            return false
        }

        var enriched = json
        enriched["finishedAt"] = ISO8601Flexible.string(from: now)
        enriched["outcome"] = outcome(for: fresh)
        guard
            let enrichedData = try? JSONSerialization.data(
                withJSONObject: enriched, options: [.sortedKeys, .prettyPrinted])
        else { return false }

        let historyDir = bundle.appendingPathComponent(
            "runs/history/\(snapshot.slug)", isDirectory: true)
        let historyURL = historyDir.appendingPathComponent("\(stamp(for: now)).json")
        do {
            try fileOps.createDirectory(at: historyDir)
            try fileOps.writeAtomic(enrichedData, to: historyURL)
            guard try fileOps.removeIfUnchanged(at: runStateURL, identity: identity) else {
                // The run-state changed under us — a resume won the race. Keep
                // the live file, roll the history copy back.
                try? fileOps.remove(at: historyURL)
                return false
            }
            return true
        } catch {
            Self.logger.warning(
                "sweep of \(snapshot.slug, privacy: .public) failed: \(error, privacy: .public)")
            try? fileOps.remove(at: historyURL)
            return false
        }
    }

    private static func isAlive(pid rawPid: Int?) -> Bool {
        guard let rawPid, let pid = pid_t(exactly: rawPid), pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    private static func stamp(for date: Date) -> String {
        ISO8601Flexible.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
