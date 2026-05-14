import Foundation
import Testing

@testable import Plumage

struct ConfigLoaderTests {
    @Test func validConfigLoads() throws {
        let folder = try TempProject.make(
            content: """
                {
                  "name": "ValidProject",
                  "schemaVersion": 2,
                  "issueIdPadding": 5
                }
                """)
        defer { try? FileManager.default.removeItem(at: folder) }

        let config = try ConfigLoader.load(at: folder)
        #expect(config.name == "ValidProject")
        #expect(config.schemaVersion == 2)
        #expect(config.issueIdPadding == 5)
    }

    @Test func missingBundleThrowsNoBundle() throws {
        let folder = try TempProject.make(content: nil)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect {
            try ConfigLoader.load(at: folder)
        } throws: { error in
            guard case ConfigLoader.LoadError.noBundle(let reported) = error else { return false }
            return reported.standardizedFileURL == folder.standardizedFileURL
        }
    }

    @Test func bundleWithoutConfigThrowsNoConfigFile() throws {
        let folder = try TempProject.make(content: nil)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = folder.appendingPathComponent("Empty.plumage", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        #expect {
            try ConfigLoader.load(at: folder)
        } throws: { error in
            guard case ConfigLoader.LoadError.noConfigFile(let reported) = error else {
                return false
            }
            return reported.standardizedFileURL == bundle.standardizedFileURL
        }
    }

    @Test func emptyFileThrowsInvalidJSON() throws {
        let folder = try TempProject.make(content: "")
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect {
            try ConfigLoader.load(at: folder)
        } throws: { error in
            if case ConfigLoader.LoadError.invalidJSON = error { return true }
            return false
        }
    }

    @Test func brokenJSONThrowsInvalidJSON() throws {
        let folder = try TempProject.make(
            content: """
                { "name": "Oops", "schemaVersion": 2,
                """)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect {
            try ConfigLoader.load(at: folder)
        } throws: { error in
            if case ConfigLoader.LoadError.invalidJSON = error { return true }
            return false
        }
    }

    @Test func futureSchemaVersionRejected() throws {
        let folder = try TempProject.make(
            content: """
                { "name": "FutureProject", "schemaVersion": 9999, "issueIdPadding": 5 }
                """)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect {
            try ConfigLoader.load(at: folder)
        } throws: { error in
            guard case ConfigLoader.LoadError.schemaTooNew(let version, let supportedUpTo) = error else {
                return false
            }
            return version == 9999 && supportedUpTo == SchemaVersion.current
        }
    }

    @Test func missingNameThrowsInvalidJSON() throws {
        let folder = try TempProject.make(
            content: """
                { "schemaVersion": 2, "issueIdPadding": 5 }
                """)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect {
            try ConfigLoader.load(at: folder)
        } throws: { error in
            guard case ConfigLoader.LoadError.invalidJSON(let message) = error else { return false }
            return message.contains("name")
        }
    }

    @Test func zeroIssueIdPaddingRejected() throws {
        let folder = try TempProject.make(
            content: """
                { "name": "Bad", "schemaVersion": 2, "issueIdPadding": 0 }
                """)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect {
            try ConfigLoader.load(at: folder)
        } throws: { error in
            guard case ConfigLoader.LoadError.invalidJSON(let message) = error else { return false }
            return message.contains("issueIdPadding")
        }
    }

    @Test func negativeIssueIdPaddingRejected() throws {
        let folder = try TempProject.make(
            content: """
                { "name": "Bad", "schemaVersion": 2, "issueIdPadding": -3 }
                """)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect {
            try ConfigLoader.load(at: folder)
        } throws: { error in
            guard case ConfigLoader.LoadError.invalidJSON(let message) = error else { return false }
            return message.contains("issueIdPadding")
        }
    }

    @Test func unknownFieldsAreIgnored() throws {
        let folder = try TempProject.make(
            content: """
                {
                  "name": "Rich",
                  "schemaVersion": 2,
                  "issueIdPadding": 5,
                  "extraUnknownField": "future-value",
                  "git": { "defaultBranch": "main" }
                }
                """)
        defer { try? FileManager.default.removeItem(at: folder) }

        let config = try ConfigLoader.load(at: folder)
        #expect(config.name == "Rich")
    }
}
