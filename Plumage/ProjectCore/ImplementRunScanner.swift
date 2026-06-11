import Foundation

nonisolated struct LiveImplementRun: Equatable, Sendable {
    let issue: String
    let agentPid: pid_t
}

nonisolated enum ImplementRunScanner {
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
                let runState = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                runState["kind"] as? String == "implement",
                let rawPid = runState["agentPid"] as? Int,
                let pid = pid_t(exactly: rawPid), pid > 0,
                kill(pid, 0) == 0
            else { continue }
            let issue =
                runState["issue"] as? String
                ?? file.deletingPathExtension().lastPathComponent
            return LiveImplementRun(issue: issue, agentPid: pid)
        }
        return nil
    }
}
