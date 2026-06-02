import Foundation

// Everything type-dependent about a project kind, bundled in one static record.
// `ProjectKind.profile` is the single source of truth; composers and the
// scaffolder read from it rather than switching on `ProjectKind` themselves.
nonisolated struct ProjectKindProfile: Hashable, Sendable {
    let templateLayers: [String]
    let gitignoreTags: [String]
    let mcpServers: [MCPServerSpec]
    let hookNames: [String]
    let gateCommands: GateCommands
    let stackSummary: String
    let xcodeMcpLine: String
}

nonisolated struct GateCommands: Codable, Hashable, Sendable {
    let build: String?
    let test: String?
    let format: String?
    let lint: String?

    static let none = GateCommands(build: nil, test: nil, format: nil, lint: nil)

    static let xcode = GateCommands(
        build: "xcodebuild build",
        test: "xcodebuild test",
        format: "swift-format lint",
        lint: "swiftlint"
    )

    static let swiftPM = GateCommands(
        build: "swift build",
        test: "swift test",
        format: "swift-format lint",
        lint: "swiftlint"
    )
}

nonisolated struct MCPServerSpec: Codable, Hashable, Sendable {
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]

    init(name: String, command: String, args: [String] = [], env: [String: String] = [:]) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
    }

    static let xcodeBuildMCP = MCPServerSpec(
        name: "XcodeBuildMCP",
        command: "npx",
        args: ["-y", "xcodebuildmcp@2.3.2", "mcp"],
        env: ["XCODEBUILDMCP_SENTRY_DISABLED": "true"]
    )
    static let xcode = MCPServerSpec(name: "xcode", command: "xcrun", args: ["mcpbridge"])
    static let applescript = MCPServerSpec(name: "applescript", command: "npx", args: ["-y", "applescript-mcp"])
    static let safari = MCPServerSpec(name: "safari", command: "npx", args: ["-y", "safari-mcp"])
}

nonisolated extension ProjectKindProfile {
    // Hook base names (without `.sh`). The `/plumage-*` workflow infrastructure
    // hooks ship with every kind; Swift tooling hooks only with Swift kinds.
    static let workflowHooks = [
        "block-dangerous-bash",
        "block-git-commit",
        "block-secret-files",
        "block-secrets-in-content",
        "force-plumage-skill",
        "stop-after-spec-approved",
    ]
    static let swiftHooks = workflowHooks + ["format-swift", "lint-swift", "no-doc-comments"]
}

nonisolated extension ProjectKind {
    var profile: ProjectKindProfile {
        switch self {
        case .appleMultiplatform:
            ProjectKindProfile(
                templateLayers: ["swift-shared", "apple-shared", "multiplatform"],
                gitignoreTags: ["swift", "xcode"],
                mcpServers: [.xcodeBuildMCP, .xcode, .applescript],
                hookNames: ProjectKindProfile.swiftHooks,
                gateCommands: .xcode,
                stackSummary: Self.appleStackSummary(buildSystem: "Xcode (single multiplatform target)", ui: "SwiftUI"),
                xcodeMcpLine: Self.xcodeMcpLine
            )
        case .macOS:
            ProjectKindProfile(
                templateLayers: ["swift-shared", "apple-shared", "macos"],
                gitignoreTags: ["swift", "xcode"],
                mcpServers: [.xcodeBuildMCP, .xcode],
                hookNames: ProjectKindProfile.swiftHooks,
                gateCommands: .xcode,
                stackSummary: Self.appleStackSummary(buildSystem: "Xcode", ui: "SwiftUI (AppKit where needed)"),
                xcodeMcpLine: Self.xcodeMcpLine
            )
        case .iOS:
            ProjectKindProfile(
                templateLayers: ["swift-shared", "apple-shared", "ios"],
                gitignoreTags: ["swift", "xcode"],
                mcpServers: [.xcodeBuildMCP, .xcode],
                hookNames: ProjectKindProfile.swiftHooks,
                gateCommands: .xcode,
                stackSummary: Self.appleStackSummary(buildSystem: "Xcode", ui: "SwiftUI (UIKit where needed)"),
                xcodeMcpLine: Self.xcodeMcpLine
            )
        case .vapor:
            ProjectKindProfile(
                templateLayers: ["swift-shared", "vapor"],
                gitignoreTags: ["swift"],
                mcpServers: [.safari],
                hookNames: ProjectKindProfile.swiftHooks,
                gateCommands: .swiftPM,
                stackSummary: Self.serverStackSummary(framework: "Vapor"),
                xcodeMcpLine: ""
            )
        case .hummingbird:
            ProjectKindProfile(
                templateLayers: ["swift-shared", "hummingbird"],
                gitignoreTags: ["swift"],
                mcpServers: [.safari],
                hookNames: ProjectKindProfile.swiftHooks,
                gateCommands: .swiftPM,
                stackSummary: Self.serverStackSummary(framework: "Hummingbird"),
                xcodeMcpLine: ""
            )
        case .swiftCLI:
            ProjectKindProfile(
                templateLayers: ["swift-shared", "swift-cli"],
                gitignoreTags: ["swift"],
                mcpServers: [],
                hookNames: ProjectKindProfile.swiftHooks,
                gateCommands: .swiftPM,
                stackSummary: """
                    - **Build system:** Swift Package Manager
                    - **Language:** Swift 6 (strict concurrency)
                    - **Test framework:** Swift Testing
                    """,
                xcodeMcpLine: ""
            )
        case .other:
            ProjectKindProfile(
                templateLayers: [],
                gitignoreTags: [],
                mcpServers: [],
                hookNames: ProjectKindProfile.workflowHooks,
                gateCommands: .none,
                stackSummary: "_(Describe your stack here.)_",
                xcodeMcpLine: ""
            )
        }
    }

    private static func appleStackSummary(buildSystem: String, ui: String) -> String {
        """
        - **Build system:** \(buildSystem)
        - **Language:** Swift 6 (strict concurrency)
        - **UI framework:** \(ui)
        - **Test framework:** Swift Testing
        """
    }

    private static func serverStackSummary(framework: String) -> String {
        """
        - **Build system:** Swift Package Manager
        - **Language:** Swift 6 (strict concurrency)
        - **Framework:** \(framework)
        - **Test framework:** Swift Testing
        """
    }

    private static let xcodeMcpLine =
        "- Apple's Xcode MCP (`xcrun mcpbridge`) is available for file ops, SwiftUI previews, and the Swift REPL."
}
