nonisolated struct IssueType: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let feature = IssueType(rawValue: "feature")
    static let chore = IssueType(rawValue: "chore")
    static let spike = IssueType(rawValue: "spike")
    static let refactor = IssueType(rawValue: "refactor")

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
