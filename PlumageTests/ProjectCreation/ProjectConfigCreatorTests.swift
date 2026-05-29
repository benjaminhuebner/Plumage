import Foundation
import Testing

@testable import Plumage

@Suite("ProjectConfigCreator")
struct ProjectConfigCreatorTests {
    private let creator = ProjectConfigCreator(createdWithPlumageVersion: "9.9.9", minPlumageVersion: "0.1.0")

    private func makeSpec(_ kind: ProjectKind, name: String = "Acme", git: GitSetup? = nil) -> NewProjectSpec {
        NewProjectSpec(
            kind: kind, name: name, tagline: "tl",
            projectDirectory: URL(filePath: "/tmp/x"), git: git)
    }

    private func json(_ spec: NewProjectSpec) throws -> [String: Any] {
        let data = try creator.makeConfigData(for: spec)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("config.json loads through ConfigLoader for every kind")
    func loadsForEveryKind() throws {
        for kind in ProjectKind.allCases {
            let tmp = FileManager.default.temporaryDirectory
                .appending(path: "PlumageCfg-\(UUID().uuidString)", directoryHint: .isDirectory)
            let bundle = tmp.appending(path: "Acme.plumage", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            try creator.write(for: makeSpec(kind), toBundle: bundle)
            let config = try ConfigLoader.load(atBundle: bundle)
            #expect(config.name == "Acme")
            #expect(config.schemaVersion == SchemaVersion.current)
            #expect(config.issueIdPadding == 5)
        }
    }

    @Test("projectType is the kind's raw value")
    func projectType() throws {
        for kind in ProjectKind.allCases {
            let obj = try json(makeSpec(kind))
            #expect(obj["projectType"] as? String == kind.rawValue)
        }
    }

    @Test("git.agentFilesInGit mirrors claudeInGit; defaults true with no repo")
    func agentFilesInGit() throws {
        func flag(_ git: GitSetup?) throws -> Bool {
            let gitObj = try #require(try json(makeSpec(.macOS, git: git))["git"] as? [String: Any])
            return try #require(gitObj["agentFilesInGit"] as? Bool)
        }
        #expect(try flag(GitSetup(claudeInGit: false)) == false)
        #expect(try flag(GitSetup(claudeInGit: true)) == true)
        #expect(try flag(nil) == true)
    }

    @Test("Base fields are present and schema-valid")
    func baseFields() throws {
        let obj = try json(makeSpec(.vapor, name: "Srv"))
        #expect(obj["schemaVersion"] as? Int == 2)
        #expect((obj["issueIdPadding"] as? Int ?? 0) >= 1)
        #expect(obj["createdWithPlumageVersion"] as? String == "9.9.9")
        #expect(obj["name"] as? String == "Srv")
        #expect(obj["createdAt"] != nil)
        #expect(obj["paths"] != nil)
        #expect(obj["plumageManaged"] != nil)
    }
}
