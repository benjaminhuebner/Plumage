import Foundation
import Testing

@testable import Plumage

@Suite("TemplateCatalog Codable round-trip")
struct TemplateCatalogCodableTests {
    private func sampleManifest() -> TemplateManifest {
        let base = BaseTemplate(
            id: "base",
            name: "Base",
            claudeMdRelativePath: "templates/CLAUDE.md",
            workflowHooks: ["block-dangerous-bash", "force-plumage-skill"]
        )
        let category = TemplateCategory(id: "appleApps", name: "Apple Apps", order: 0)
        let swiftShared = SharedComponent(
            id: "swift-shared",
            name: "Swift Shared",
            kind: .layer,
            files: ["swift-shared"],
            order: 0,
            memberTemplateIDs: ["macOS", "iOS", "vapor"]
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
            mcpServers: [.xcodeBuildMCP, .xcode],
            gateCommands: .xcode,
            stackSummary: "- **Build system:** Xcode",
            xcodeMcpLine: "- Apple's Xcode MCP is available."
        )
        return TemplateManifest(
            schemaVersion: TemplateManifest.currentSchemaVersion,
            base: base,
            categories: [category],
            sharedComponents: [swiftShared],
            templates: [descriptor]
        )
    }

    @Test("Manifest survives an encode/decode round-trip unchanged")
    func manifestRoundTrip() throws {
        let original = sampleManifest()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TemplateManifest.self, from: data)
        #expect(decoded == original)
    }

    @Test("TemplateImage encodes its associated symbol")
    func templateImageRoundTrip() throws {
        let image = TemplateImage.symbol("macwindow")
        let decoded = try JSONDecoder().decode(
            TemplateImage.self, from: JSONEncoder().encode(image))
        #expect(decoded == image)
    }

    @Test("TemplateImage.file round-trips its relative path")
    func templateImageFileRoundTrip() throws {
        let image = TemplateImage.file("template-images/custom.png")
        let decoded = try JSONDecoder().decode(
            TemplateImage.self, from: JSONEncoder().encode(image))
        #expect(decoded == image)
    }

    @Test("SharedComponent membership query")
    func sharedComponentMembership() {
        let component = sampleManifest().sharedComponents[0]
        #expect(component.isMember("macOS"))
        #expect(!component.isMember("other"))
    }
}
