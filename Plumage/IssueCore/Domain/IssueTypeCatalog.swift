import Foundation

nonisolated struct IssueTypeDefinition: Hashable, Sendable, Codable, Identifiable {
    let type: IssueType
    var draftBlocksImplement: Bool
    // sRGB "#RRGGBB"; nil = the built-in fixed color or the hash palette.
    var colorHex: String?

    var id: String { type.rawValue }

    init(type: IssueType, draftBlocksImplement: Bool, colorHex: String? = nil) {
        self.type = type
        self.draftBlocksImplement = draftBlocksImplement
        self.colorHex = colorHex
    }

    enum CodingKeys: String, CodingKey {
        case name
        case draftBlocksImplement
        case color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = IssueType(rawValue: try container.decode(String.self, forKey: .name))
        draftBlocksImplement =
            try container.decodeIfPresent(Bool.self, forKey: .draftBlocksImplement) ?? true
        colorHex = try container.decodeIfPresent(String.self, forKey: .color)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type.rawValue, forKey: .name)
        try container.encode(draftBlocksImplement, forKey: .draftBlocksImplement)
        try container.encodeIfPresent(colorHex, forKey: .color)
    }
}

nonisolated struct IssueTypeCatalog: Hashable, Sendable, Codable {
    private(set) var definitions: [IssueTypeDefinition]
    private(set) var defaultTypeName: String?

    enum CodingKeys: String, CodingKey {
        case definitions = "types"
        case defaultTypeName = "defaultType"
    }

    init(definitions: [IssueTypeDefinition], defaultTypeName: String? = nil) {
        self.definitions = definitions
        self.defaultTypeName = defaultTypeName
    }

    static let builtIn = IssueTypeCatalog(definitions: [
        IssueTypeDefinition(type: .feature, draftBlocksImplement: true),
        IssueTypeDefinition(type: .chore, draftBlocksImplement: false),
        IssueTypeDefinition(type: .spike, draftBlocksImplement: false),
        IssueTypeDefinition(type: .refactor, draftBlocksImplement: false),
    ])

    var types: [IssueType] { definitions.map(\.type) }

    // A stored default that was deleted from the catalog falls back to the
    // first type instead of leaking into new issues.
    var defaultType: IssueType {
        if let name = defaultTypeName {
            let stored = IssueType(rawValue: name)
            if contains(stored) { return stored }
        }
        return definitions.first?.type ?? .feature
    }

    func contains(_ type: IssueType) -> Bool {
        definitions.contains { $0.type == type }
    }

    func definition(for type: IssueType) -> IssueTypeDefinition? {
        definitions.first { $0.type == type }
    }

    // Unknown types (deleted from the catalog, or a typo) fall back to
    // blocking: implementing an unvetted draft is the risky direction.
    func draftBlocksImplement(for type: IssueType) -> Bool {
        definitions.first { $0.type == type }?.draftBlocksImplement ?? true
    }

    mutating func add(name: String, colorHex: String? = nil) throws {
        let normalized = Self.normalize(name)
        guard Self.isValidName(normalized) else {
            throw IssueTypeCatalogError.invalidName(normalized)
        }
        let type = IssueType(rawValue: normalized)
        guard !contains(type) else {
            throw IssueTypeCatalogError.duplicateName(normalized)
        }
        definitions.append(
            IssueTypeDefinition(type: type, draftBlocksImplement: true, colorHex: colorHex))
    }

    mutating func remove(_ type: IssueType) throws {
        guard definitions.count > 1 else {
            throw IssueTypeCatalogError.lastTypeUndeletable
        }
        definitions.removeAll { $0.type == type }
        if defaultTypeName == type.rawValue { defaultTypeName = nil }
    }

    mutating func setDraftBlocksImplement(_ blocks: Bool, for type: IssueType) {
        guard let index = definitions.firstIndex(where: { $0.type == type }) else { return }
        definitions[index].draftBlocksImplement = blocks
    }

    mutating func setColor(_ hex: String?, for type: IssueType) {
        guard let index = definitions.firstIndex(where: { $0.type == type }) else { return }
        definitions[index].colorHex = hex
    }

    mutating func setDefaultType(_ type: IssueType) {
        guard contains(type) else { return }
        defaultTypeName = type.rawValue
    }

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Type names live in spec frontmatter and in `#if` directive tokens, so
    // they must survive whitespace-splitting shell/YAML parsing: lowercase
    // alphanumerics and inner hyphens only.
    static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 30 else { return false }
        guard name.first != "-", name.last != "-" else { return false }
        return name.allSatisfy { character in
            character.isASCII && (character.isLowercase || character.isNumber || character == "-")
        }
    }
}

nonisolated enum IssueTypeCatalogError: Error, Equatable, LocalizedError {
    case invalidName(String)
    case duplicateName(String)
    case lastTypeUndeletable

    var errorDescription: String? {
        switch self {
        case .invalidName:
            "Type names use lowercase letters, digits, and inner hyphens (e.g. “docs” or “tech-debt”)."
        case .duplicateName(let name):
            "A type named “\(name)” already exists."
        case .lastTypeUndeletable:
            "At least one issue type must remain."
        }
    }
}
