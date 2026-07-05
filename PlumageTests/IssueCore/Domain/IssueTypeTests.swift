import SwiftUI
import Testing

@testable import Plumage

@Suite("IssueType")
struct IssueTypeTests {
    @Test("built-in types map to their fixed colors")
    func builtInColors() {
        #expect(IssueType.feature.color == Color.green)
        #expect(IssueType.chore.color == Color.yellow)
        #expect(IssueType.spike.color == Color.orange)
        #expect(IssueType.refactor.color == Color.cyan)
    }

    @Test("custom types get a stable label-palette color")
    func customTypeColor() {
        let docs = IssueType(rawValue: "docs")
        #expect(docs.color == LabelColor.color(for: "docs"))
        #expect(docs.color == IssueType(rawValue: "docs").color)
    }

    @Test("rawValue round-trips through Codable as a plain string")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode([IssueType(rawValue: "tech-debt"), .feature])
        #expect(String(data: data, encoding: .utf8) == #"["tech-debt","feature"]"#)
        let decoded = try JSONDecoder().decode([IssueType].self, from: data)
        #expect(decoded == [IssueType(rawValue: "tech-debt"), .feature])
    }

    @Test("built-in constants carry the frontmatter tokens")
    func builtInRawValues() {
        #expect(IssueType.feature.rawValue == "feature")
        #expect(IssueType.chore.rawValue == "chore")
        #expect(IssueType.spike.rawValue == "spike")
        #expect(IssueType.refactor.rawValue == "refactor")
    }
}

@Suite("IssueTypeCatalog")
struct IssueTypeCatalogTests {
    @Test("built-in catalog carries the four legacy types in order")
    func builtInTypes() {
        #expect(IssueTypeCatalog.builtIn.types == [.feature, .chore, .spike, .refactor])
        #expect(IssueTypeCatalog.builtIn.defaultType == .feature)
    }

    @Test("built-in draft-block flags mirror the legacy gating: only feature blocks")
    func builtInFlags() {
        let catalog = IssueTypeCatalog.builtIn
        #expect(catalog.draftBlocksImplement(for: .feature))
        #expect(!catalog.draftBlocksImplement(for: .chore))
        #expect(!catalog.draftBlocksImplement(for: .spike))
        #expect(!catalog.draftBlocksImplement(for: .refactor))
    }

    @Test("unknown types block implement from draft")
    func unknownTypeBlocks() {
        #expect(IssueTypeCatalog.builtIn.draftBlocksImplement(for: IssueType(rawValue: "ghost")))
    }

    @Test("add normalizes, validates, and appends with blocking default")
    func addType() throws {
        var catalog = IssueTypeCatalog.builtIn
        try catalog.add(name: "  Tech-Debt ")
        let added = try #require(catalog.definitions.last)
        #expect(added.type.rawValue == "tech-debt")
        #expect(added.draftBlocksImplement)
    }

    @Test("add rejects invalid names")
    func addInvalidName() {
        var catalog = IssueTypeCatalog.builtIn
        for name in ["", "two words", "Ümlaut", "-lead", "trail-", "under_score"] {
            #expect(throws: IssueTypeCatalogError.invalidName(IssueTypeCatalog.normalize(name))) {
                try catalog.add(name: name)
            }
        }
    }

    @Test("add rejects duplicates case-insensitively")
    func addDuplicate() {
        var catalog = IssueTypeCatalog.builtIn
        #expect(throws: IssueTypeCatalogError.duplicateName("feature")) {
            try catalog.add(name: "Feature")
        }
    }

    @Test("remove drops the type; the last remaining type is undeletable")
    func removeType() throws {
        var catalog = IssueTypeCatalog.builtIn
        try catalog.remove(.chore)
        #expect(!catalog.contains(.chore))
        try catalog.remove(.spike)
        try catalog.remove(.refactor)
        #expect(throws: IssueTypeCatalogError.lastTypeUndeletable) {
            try catalog.remove(.feature)
        }
        #expect(catalog.types == [.feature])
    }

    @Test("setDraftBlocksImplement flips the flag; unknown type is a no-op")
    func setFlag() {
        var catalog = IssueTypeCatalog.builtIn
        catalog.setDraftBlocksImplement(false, for: .feature)
        #expect(!catalog.draftBlocksImplement(for: .feature))
        let before = catalog
        catalog.setDraftBlocksImplement(false, for: IssueType(rawValue: "ghost"))
        #expect(catalog == before)
    }

    @Test("JSON round-trips through the on-disk shape with name keys")
    func jsonRoundTrip() throws {
        var catalog = IssueTypeCatalog.builtIn
        try catalog.add(name: "docs")
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(IssueTypeCatalog.self, from: data)
        #expect(decoded == catalog)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let types = try #require(object?["types"] as? [[String: Any]])
        #expect(types.first?["name"] as? String == "feature")
        #expect(types.first?["draftBlocksImplement"] as? Bool == true)
    }

    @Test("a missing draftBlocksImplement key decodes as blocking")
    func missingFlagDefaultsToBlocking() throws {
        let json = #"{"types": [{"name": "feature"}, {"name": "chore", "draftBlocksImplement": false}]}"#
        let catalog = try JSONDecoder().decode(IssueTypeCatalog.self, from: Data(json.utf8))
        #expect(catalog.draftBlocksImplement(for: .feature))
        #expect(!catalog.draftBlocksImplement(for: .chore))
    }

    @Test("custom color hex round-trips; clearing falls back to nil")
    func colorRoundTrip() throws {
        var catalog = IssueTypeCatalog.builtIn
        catalog.setColor("#FF8800", for: .chore)
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(IssueTypeCatalog.self, from: data)
        #expect(decoded.definition(for: .chore)?.colorHex == "#FF8800")
        #expect(decoded.definition(for: .feature)?.colorHex == nil)
        catalog.setColor(nil, for: .chore)
        #expect(catalog.definition(for: .chore)?.colorHex == nil)
    }

    @Test("add stores a chosen color; setColor on an unknown type is a no-op")
    func addWithColor() throws {
        var catalog = IssueTypeCatalog.builtIn
        try catalog.add(name: "docs", colorHex: "#123456")
        #expect(catalog.definition(for: IssueType(rawValue: "docs"))?.colorHex == "#123456")
        let before = catalog
        catalog.setColor("#000000", for: IssueType(rawValue: "ghost"))
        #expect(catalog == before)
    }

    @Test("default type: stored wins, deleted or missing falls back to first")
    func defaultTypeResolution() throws {
        var catalog = IssueTypeCatalog.builtIn
        #expect(catalog.defaultType == .feature)
        catalog.setDefaultType(.spike)
        #expect(catalog.defaultType == .spike)
        try catalog.remove(.spike)
        #expect(catalog.defaultTypeName == nil)
        #expect(catalog.defaultType == .feature)
        catalog.setDefaultType(IssueType(rawValue: "ghost"))
        #expect(catalog.defaultType == .feature)
    }

    @Test("default type round-trips through JSON; stale stored name degrades to first")
    func defaultTypeCodable() throws {
        var catalog = IssueTypeCatalog.builtIn
        catalog.setDefaultType(.chore)
        let data = try JSONEncoder().encode(catalog)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["defaultType"] as? String == "chore")
        let decoded = try JSONDecoder().decode(IssueTypeCatalog.self, from: data)
        #expect(decoded.defaultType == .chore)
        let stale = #"{"defaultType": "gone", "types": [{"name": "chore"}, {"name": "spike"}]}"#
        let staleCatalog = try JSONDecoder().decode(IssueTypeCatalog.self, from: Data(stale.utf8))
        #expect(staleCatalog.defaultType == .chore)
    }
}

@Suite("IssueTypeCatalogStore")
struct IssueTypeCatalogStoreTests {
    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "issue-type-store-tests-\(UUID().uuidString)")
            .appending(path: "issue-types.json")
    }

    @Test("missing file loads the built-in catalog")
    func missingFile() {
        let store = IssueTypeCatalogStore(fileURL: temporaryFileURL())
        #expect(store.load() == .builtIn)
    }

    @Test("save/load round-trips a customized catalog")
    func roundTrip() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var catalog = IssueTypeCatalog.builtIn
        try catalog.add(name: "docs")
        catalog.setDraftBlocksImplement(false, for: .feature)
        let store = IssueTypeCatalogStore(fileURL: url)
        try store.save(catalog)
        #expect(store.load() == catalog)
    }

    @Test("corrupt or empty catalogs fall back to the built-in")
    func corruptFallsBack() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = IssueTypeCatalogStore(fileURL: url)
        #expect(store.load() == .builtIn)
        try Data(#"{"types": []}"#.utf8).write(to: url)
        #expect(store.load() == .builtIn)
    }
}
