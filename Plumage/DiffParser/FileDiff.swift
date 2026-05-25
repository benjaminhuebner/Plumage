import Foundation

nonisolated public struct FileDiff: Sendable, Equatable, Hashable {
    public let path: String
    public let status: FileStatus
    public let modeChange: ModeChange?
    public let hunks: [Hunk]

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
