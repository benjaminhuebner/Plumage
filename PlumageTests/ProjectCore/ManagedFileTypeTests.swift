import Foundation
import Testing

@testable import Plumage

@Suite("ManagedFileType")
struct ManagedFileTypeTests {
    @Test("allCases covers docs/hooks/agents/rules/outputStyles in stable order")
    func allCasesShape() {
        #expect(ManagedFileType.allCases == [.docs, .hooks, .agents, .rules, .outputStyles])
    }

    @Test(
        "relativePath stays under .claude/",
        arguments: ManagedFileType.allCases
    )
    func relativePathUnderClaude(type: ManagedFileType) {
        #expect(type.relativePath.hasPrefix(".claude/"))
    }

    @Test(
        "allowedExtensions is non-empty and contains defaultExtension",
        arguments: ManagedFileType.allCases
    )
    func allowedExtensionsContainDefault(type: ManagedFileType) {
        #expect(!type.allowedExtensions.isEmpty)
        #expect(type.allowedExtensions.contains(type.defaultExtension))
    }

    @Test(
        "defaultName uses default extension",
        arguments: ManagedFileType.allCases
    )
    func defaultNameUsesExtension(type: ManagedFileType) {
        #expect(type.defaultName == "untitled.\(type.defaultExtension)")
    }

    @Test("recursive is true only for agents and rules")
    func recursiveOnlyAgentsRules() {
        #expect(ManagedFileType.agents.recursive)
        #expect(ManagedFileType.rules.recursive)
        #expect(!ManagedFileType.docs.recursive)
        #expect(!ManagedFileType.hooks.recursive)
        #expect(!ManagedFileType.outputStyles.recursive)
    }

    @Test("allowsSubfolders matches recursive plus hooks")
    func allowsSubfoldersShape() {
        #expect(ManagedFileType.agents.allowsSubfolders)
        #expect(ManagedFileType.rules.allowsSubfolders)
        #expect(ManagedFileType.hooks.allowsSubfolders)
        #expect(!ManagedFileType.docs.allowsSubfolders)
        #expect(!ManagedFileType.outputStyles.allowsSubfolders)
    }

    @Test(
        "sectionTitle is non-empty",
        arguments: ManagedFileType.allCases
    )
    func sectionTitleNonEmpty(type: ManagedFileType) {
        #expect(!type.sectionTitle.isEmpty)
    }

    @Test("sectionTitle uses the spec's wording")
    func sectionTitlesMatchSpec() {
        #expect(ManagedFileType.docs.sectionTitle == "Docs")
        #expect(ManagedFileType.hooks.sectionTitle == "Hooks")
        #expect(ManagedFileType.agents.sectionTitle == "Agents")
        #expect(ManagedFileType.rules.sectionTitle == "Rules")
        #expect(ManagedFileType.outputStyles.sectionTitle == "Output Styles")
    }

    @Test("defaultStub for docs is blank (matches legacy createDoc)")
    func defaultStubDocsBlank() {
        #expect(ManagedFileType.docs.defaultStub(filename: "intro.md").isEmpty)
    }

    @Test("defaultStub for hooks emits shebang based on extension")
    func defaultStubHooksShebang() {
        #expect(
            ManagedFileType.hooks.defaultStub(filename: "lint.sh")
                .hasPrefix("#!/usr/bin/env bash"))
        #expect(
            ManagedFileType.hooks.defaultStub(filename: "extract.py")
                .hasPrefix("#!/usr/bin/env python3"))
    }

    @Test(
        "defaultStub for markdown types emits YAML frontmatter with the file stem",
        arguments: [ManagedFileType.agents, .rules, .outputStyles]
    )
    func defaultStubMarkdownFrontmatter(type: ManagedFileType) {
        let stub = type.defaultStub(filename: "reviewer.md")
        #expect(stub.contains("---"))
        #expect(stub.contains("name: reviewer"))
        #expect(stub.contains("description:"))
    }

    @Test(
        "rejectionMessage mentions the section name",
        arguments: ManagedFileType.allCases
    )
    func rejectionMessageMentionsSection(type: ManagedFileType) {
        #expect(type.rejectionMessage.localizedCaseInsensitiveContains(type.sectionTitle))
    }

    @Test("Codable round-trip preserves cases")
    func codableRoundTrip() throws {
        for type in ManagedFileType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(ManagedFileType.self, from: data)
            #expect(decoded == type)
        }
    }
}
