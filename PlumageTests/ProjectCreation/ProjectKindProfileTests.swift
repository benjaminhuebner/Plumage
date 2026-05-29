import Foundation
import Testing

@testable import Plumage

@Suite("ProjectKindProfile")
struct ProjectKindProfileTests {
    private func mcpNames(_ kind: ProjectKind) -> [String] {
        kind.profile.mcpServers.map(\.name)
    }

    @Test("Template layers per kind")
    func templateLayers() {
        #expect(
            ProjectKind.appleMultiplatform.profile.templateLayers
                == ["swift-shared", "apple-shared", "multiplatform"])
        #expect(
            ProjectKind.macOS.profile.templateLayers
                == ["swift-shared", "apple-shared", "macos"])
        #expect(
            ProjectKind.iOS.profile.templateLayers
                == ["swift-shared", "apple-shared", "ios"])
        #expect(ProjectKind.vapor.profile.templateLayers == ["swift-shared", "vapor"])
        #expect(ProjectKind.hummingbird.profile.templateLayers == ["swift-shared", "hummingbird"])
        #expect(ProjectKind.swiftCLI.profile.templateLayers == ["swift-shared", "swift-cli"])
        #expect(ProjectKind.other.profile.templateLayers.isEmpty)
    }

    @Test("Gitignore tags per kind (macOS is appended later by the composer)")
    func gitignoreTags() {
        #expect(ProjectKind.macOS.profile.gitignoreTags == ["swift", "xcode"])
        #expect(ProjectKind.iOS.profile.gitignoreTags == ["swift", "xcode"])
        #expect(ProjectKind.appleMultiplatform.profile.gitignoreTags == ["swift", "xcode"])
        #expect(ProjectKind.vapor.profile.gitignoreTags == ["swift"])
        #expect(ProjectKind.hummingbird.profile.gitignoreTags == ["swift"])
        #expect(ProjectKind.swiftCLI.profile.gitignoreTags == ["swift"])
        #expect(ProjectKind.other.profile.gitignoreTags.isEmpty)
    }

    @Test("MCP servers per kind")
    func mcpServers() {
        #expect(mcpNames(.appleMultiplatform) == ["XcodeBuildMCP", "xcode", "applescript"])
        #expect(mcpNames(.macOS) == ["XcodeBuildMCP", "xcode"])
        #expect(mcpNames(.iOS) == ["XcodeBuildMCP", "xcode"])
        #expect(mcpNames(.vapor) == ["safari"])
        #expect(mcpNames(.hummingbird) == ["safari"])
        #expect(mcpNames(.swiftCLI).isEmpty)
        #expect(mcpNames(.other).isEmpty)

        let xcodeBuild = ProjectKind.macOS.profile.mcpServers[0]
        #expect(xcodeBuild.command == "npx")
        #expect(xcodeBuild.args == ["-y", "xcodebuildmcp@2.3.2", "mcp"])
        #expect(xcodeBuild.env == ["XCODEBUILDMCP_SENTRY_DISABLED": "true"])
    }

    @Test("Hook sets: workflow ⊂ swift ⊂ apple; .other gets only workflow hooks")
    func hookNames() {
        #expect(ProjectKind.macOS.profile.hookNames == ProjectKindProfile.appleHooks)
        #expect(ProjectKind.iOS.profile.hookNames == ProjectKindProfile.appleHooks)
        #expect(ProjectKind.appleMultiplatform.profile.hookNames == ProjectKindProfile.appleHooks)
        #expect(ProjectKind.vapor.profile.hookNames == ProjectKindProfile.swiftHooks)
        #expect(ProjectKind.hummingbird.profile.hookNames == ProjectKindProfile.swiftHooks)
        #expect(ProjectKind.swiftCLI.profile.hookNames == ProjectKindProfile.swiftHooks)
        #expect(ProjectKind.other.profile.hookNames == ProjectKindProfile.workflowHooks)

        #expect(ProjectKind.macOS.profile.hookNames.contains("guard-xcodebuild"))
        #expect(!ProjectKind.vapor.profile.hookNames.contains("guard-xcodebuild"))
        #expect(ProjectKind.vapor.profile.hookNames.contains("format-swift"))
        #expect(!ProjectKind.other.profile.hookNames.contains("format-swift"))
        #expect(ProjectKind.other.profile.hookNames.contains("force-plumage-skill"))
    }

    @Test("Gate commands: Xcode for Apple, SwiftPM for server/CLI, none for .other")
    func gateCommands() {
        #expect(ProjectKind.macOS.profile.gateCommands == .xcode)
        #expect(ProjectKind.iOS.profile.gateCommands == .xcode)
        #expect(ProjectKind.appleMultiplatform.profile.gateCommands == .xcode)
        #expect(ProjectKind.vapor.profile.gateCommands == .swiftPM)
        #expect(ProjectKind.hummingbird.profile.gateCommands == .swiftPM)
        #expect(ProjectKind.swiftCLI.profile.gateCommands == .swiftPM)
        #expect(ProjectKind.other.profile.gateCommands == .none)

        #expect(GateCommands.xcode.build == "xcodebuild build")
        #expect(GateCommands.swiftPM.build == "swift build")
        #expect(GateCommands.none.build == nil)
    }

    @Test("Scalar CLAUDE.md tokens: Apple kinds carry the Xcode MCP line, others don't")
    func scalarTokens() {
        #expect(!ProjectKind.macOS.profile.xcodeMcpLine.isEmpty)
        #expect(ProjectKind.macOS.profile.xcodeMcpLine.contains("mcpbridge"))
        #expect(ProjectKind.vapor.profile.xcodeMcpLine.isEmpty)
        #expect(ProjectKind.swiftCLI.profile.xcodeMcpLine.isEmpty)

        #expect(ProjectKind.macOS.profile.stackSummary.contains("Swift 6"))
        #expect(ProjectKind.vapor.profile.stackSummary.contains("Vapor"))
        #expect(ProjectKind.other.profile.stackSummary.contains("Describe your stack"))
    }
}
