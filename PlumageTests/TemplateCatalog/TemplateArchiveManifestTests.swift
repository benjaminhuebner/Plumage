import Foundation
import Testing

@testable import Plumage

@Suite("TemplateArchiveManifest Codable")
struct TemplateArchiveManifestTests {
    private func sampleManifest() -> TemplateArchiveManifest {
        let base = BaseTemplate(
            id: "base",
            name: "Base",
            claudeMdRelativePath: "templates/CLAUDE.md",
            workflowHooks: ["block-dangerous-bash"]
        )
        let category = TemplateCategory(id: "appleApps", name: "Apple Apps", order: 0)
        let component = SharedComponent(
            id: "swift-shared",
            name: "Swift Shared",
            files: [ComponentFile(kind: .layer, name: "swift-shared")],
            order: 0,
            memberTemplateIDs: ["macOS"]
        )
        let descriptor = TemplateDescriptor(
            id: "macOS",
            name: "macOS App",
            image: .symbol("macwindow"),
            categoryID: "appleApps",
            predefined: true,
            order: 1,
            templateLayers: ["macos"],
            gitignoreTags: ["swift", "xcode"],
            mcpServers: [.xcodeBuildMCP],
            gateCommands: .xcode,
            stackSummary: "- **Build system:** Xcode",
            xcodeMcpLine: "- Apple's Xcode MCP is available."
        )
        return TemplateArchiveManifest(
            base: base,
            categories: [category],
            sharedComponents: [component],
            templates: [descriptor],
            tombstones: [Tombstone(kind: .template, id: "gone")],
            hookWirings: [HookWiring(name: "format-swift", event: .postToolUse, matcher: "Edit")]
        )
    }

    @Test("Manifest survives an encode/decode round-trip unchanged")
    func roundTrip() throws {
        let original = sampleManifest()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TemplateArchiveManifest.self, from: data)
        #expect(decoded == original)
    }

    @Test("Unknown top-level keys are ignored on decode")
    func unknownKeysTolerated() throws {
        let data = try JSONEncoder().encode(sampleManifest())
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["futureFeature"] = ["nested": true]
        let augmented = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TemplateArchiveManifest.self, from: augmented)
        #expect(decoded == sampleManifest())
    }

    @Test("Missing collections decode to empty, missing base to nil")
    func missingCollectionsDecodeEmpty() throws {
        let json = """
            {"schemaVersion": 1}
            """
        let decoded = try JSONDecoder().decode(
            TemplateArchiveManifest.self, from: Data(json.utf8))
        #expect(decoded.base == nil)
        #expect(decoded.categories.isEmpty)
        #expect(decoded.sharedComponents.isEmpty)
        #expect(decoded.templates.isEmpty)
        #expect(decoded.tombstones.isEmpty)
        #expect(decoded.hookWirings.isEmpty)
    }

    @Test("A newer schemaVersion is rejected with newerSchema")
    func newerSchemaRejected() throws {
        let json = """
            {"schemaVersion": 2, "templates": []}
            """
        #expect(throws: TemplateArchiveManifestError.newerSchema(found: 2, supported: 1)) {
            try JSONDecoder().decode(TemplateArchiveManifest.self, from: Data(json.utf8))
        }
    }

    @Test("A missing schemaVersion fails decoding")
    func missingSchemaVersionRejected() {
        let json = """
            {"templates": []}
            """
        #expect(throws: Error.self) {
            try JSONDecoder().decode(TemplateArchiveManifest.self, from: Data(json.utf8))
        }
    }
}
