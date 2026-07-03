import Foundation

nonisolated struct RunHistoryRecord: Equatable, Sendable {
    let state: RunState
    let finishedAt: Date?
    let outcome: String?

    enum OutcomeKind: Equatable, Sendable {
        case completed
        case failed
        case crashed
    }

    var outcomeKind: OutcomeKind {
        guard let outcome else { return .crashed }
        if outcome == "completed" { return .completed }
        if outcome.hasPrefix("failed") { return .failed }
        return .crashed
    }
}

nonisolated enum RunHistoryReader {
    struct Page: Equatable, Sendable {
        let records: [RunHistoryRecord]
        let totalCount: Int

        static let empty = Page(records: [], totalCount: 0)
    }

    static func page(forSlug slug: String, acrossRoots roots: [URL], limit: Int = 20) -> Page {
        var records: [RunHistoryRecord] = []
        var total = 0
        for root in roots {
            guard let bundle = try? BundleResolver.findBundle(in: root) else { continue }
            let dir = bundle.appendingPathComponent("runs/history/\(slug)", isDirectory: true)
            let files =
                ((try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil,
                    options: [.skipsSubdirectoryDescendants])) ?? [])
                .filter { $0.pathExtension == "json" }
            for file in files {
                guard
                    let data = try? Data(contentsOf: file),
                    let state = try? RunStateReader.decode(data),
                    let envelope = try? RunStateReader.makeDecoder()
                        .decode(HistoryEnvelope.self, from: data)
                else { continue }
                total += 1
                records.append(
                    RunHistoryRecord(
                        state: state, finishedAt: envelope.finishedAt, outcome: envelope.outcome))
            }
        }
        records.sort {
            ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast)
        }
        return Page(records: Array(records.prefix(limit)), totalCount: total)
    }
}

private nonisolated struct HistoryEnvelope: Codable {
    let finishedAt: Date?
    let outcome: String?
}
