import Foundation

nonisolated struct RunEvidence: Sendable, Equatable {
    nonisolated struct TaskRecord: Sendable, Equatable {
        let task: Int
        let attempts: Int
        let passedAt: Date?
        let head: String?
        let flags: [String]
    }

    nonisolated struct FinalGateRecord: Sendable, Equatable {
        let attempts: Int
        let passedAt: Date?
        let head: String?
        let flags: [String]
    }

    let version: Int
    let issue: String
    let branch: String?
    let totalTasks: Int?
    let tasks: [TaskRecord]
    let finalGate: FinalGateRecord?
}

nonisolated extension RunEvidence: Decodable {
    private enum CodingKeys: String, CodingKey {
        case version, issue, branch, totalTasks, tasks, finalGate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        issue = try container.decode(String.self, forKey: .issue)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        totalTasks = try container.decodeIfPresent(Int.self, forKey: .totalTasks)
        tasks = try container.decodeIfPresent([TaskRecord].self, forKey: .tasks) ?? []
        finalGate = try container.decodeIfPresent(FinalGateRecord.self, forKey: .finalGate)
    }
}

nonisolated extension RunEvidence.TaskRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case task, attempts, passedAt, head, flags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        task = try container.decode(Int.self, forKey: .task)
        attempts = try container.decode(Int.self, forKey: .attempts)
        passedAt = try container.decodeIfPresent(Date.self, forKey: .passedAt)
        head = try container.decodeIfPresent(String.self, forKey: .head)
        flags = try container.decodeIfPresent([String].self, forKey: .flags) ?? []
    }
}

nonisolated extension RunEvidence.FinalGateRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case attempts, passedAt, head, flags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attempts = try container.decode(Int.self, forKey: .attempts)
        passedAt = try container.decodeIfPresent(Date.self, forKey: .passedAt)
        head = try container.decodeIfPresent(String.self, forKey: .head)
        flags = try container.decodeIfPresent([String].self, forKey: .flags) ?? []
    }
}
