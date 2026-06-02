import Foundation

nonisolated public struct FileDiff: Sendable, Equatable, Hashable {
    public let path: String
    public let status: FileStatus
    public let modeChange: ModeChange?
    public let hunks: [Hunk]
    // Computed once here so views don't re-reduce over every hunk line on each
    // body evaluation.
    public let addedCount: Int
    public let removedCount: Int

    public init(
        path: String,
        status: FileStatus,
        modeChange: ModeChange? = nil,
        hunks: [Hunk] = []
    ) {
        self.path = path
        self.status = status
        self.modeChange = modeChange
        self.hunks = hunks
        var added = 0
        var removed = 0
        for hunk in hunks {
            for line in hunk.lines {
                switch line.kind {
                case .added: added += 1
                case .removed: removed += 1
                case .context: break
                }
            }
        }
        self.addedCount = added
        self.removedCount = removed
    }
}

nonisolated public enum FileStatus: Sendable, Equatable, Hashable {
    case added
    case modified
    case deleted
    case renamed(from: String)
    case copied(from: String)
    case binary
    case submodule(from: String, to: String)
}

nonisolated public struct ModeChange: Sendable, Equatable, Hashable {
    public let old: String
    public let new: String

    public init(old: String, new: String) {
        self.old = old
        self.new = new
    }
}
