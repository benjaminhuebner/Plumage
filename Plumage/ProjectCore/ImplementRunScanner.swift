import Foundation
import os

nonisolated struct LiveImplementRun: Equatable, Sendable {
    let issue: String
    let agentPid: pid_t
}

nonisolated struct QueuedImplementRun: Equatable, Sendable {
    let issue: String
    let agentPid: pid_t
}

nonisolated struct WorktreeImplementRun: Equatable, Sendable {
    let checkoutRoot: URL
    let run: LiveImplementRun
}

nonisolated enum ImplementRunScanner {
    private static let logger = Logger(subsystem: "com.plumage", category: "ImplementRunScanner")

    static func liveImplementRun(in projectRoot: URL) -> LiveImplementRun? {
        guard let bundle = try? BundleResolver.findBundle(in: projectRoot) else { return nil }
        let runsDir = bundle.appendingPathComponent("runs", isDirectory: true)
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: runsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )) ?? []

        for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension == "json" {
            // Malformed run-state or missing/zero/non-numeric agentPid is a
            // crash leftover, never a blocker. Validate the pid before the
            // kill(pid, 0) probe — kill(0, 0) probes our own process group.
            guard
                let data = try? Data(contentsOf: file),
                let runState = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else {
                Self.logger.warning(
                    "run-state \(file.lastPathComponent, privacy: .public) is not a JSON object — skipping"
                )
                continue
            }
            guard let kind = runState["kind"] as? String else {
                Self.logger.warning(
                    "run-state \(file.lastPathComponent, privacy: .public) has no kind — skipping")
                continue
            }
            guard kind == "implement" else { continue }
            guard let rawPid = runState["agentPid"] as? Int, let pid = pid_t(exactly: rawPid)
            else {
                Self.logger.warning(
                    "run-state \(file.lastPathComponent, privacy: .public) has no numeric agentPid — skipping"
                )
                continue
            }
            guard pid > 0, kill(pid, 0) == 0 else { continue }
            let issue =
                runState["issue"] as? String
                ?? file.deletingPathExtension().lastPathComponent
            return LiveImplementRun(issue: issue, agentPid: pid)
        }
        return nil
    }

    static func liveImplementRuns(acrossWorktreeRoots roots: [URL]) -> [WorktreeImplementRun] {
        roots.compactMap { root in
            liveImplementRun(in: root).map { WorktreeImplementRun(checkoutRoot: root, run: $0) }
        }
    }

    static func runStateExists(for slug: String, in projectRoot: URL) -> Bool {
        guard let bundle = try? BundleResolver.findBundle(in: projectRoot) else { return false }
        return FileManager.default.fileExists(
            atPath: bundle.appendingPathComponent("runs/\(slug).json").path)
    }

    // Zero-padded filename order (seq from wait-for-turn.sh) is FIFO order.
    // Read-only: dead waiters are skipped here; removing them stays with the
    // scripts.
    static func queuedImplementRuns(in projectRoot: URL) -> [QueuedImplementRun] {
        guard let bundle = try? BundleResolver.findBundle(in: projectRoot) else { return [] }
        let queueDir = bundle.appendingPathComponent("runs/queue", isDirectory: true)
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: queueDir,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )) ?? []

        var queued: [QueuedImplementRun] = []
        for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let slug = entry["slug"] as? String,
                let rawPid = entry["agentPid"] as? Int,
                let pid = pid_t(exactly: rawPid)
            else {
                Self.logger.warning(
                    "queue entry \(file.lastPathComponent, privacy: .public) has an unexpected shape — skipping"
                )
                continue
            }
            guard pid > 0, kill(pid, 0) == 0 else { continue }
            queued.append(QueuedImplementRun(issue: slug, agentPid: pid))
        }
        return queued
    }
}
