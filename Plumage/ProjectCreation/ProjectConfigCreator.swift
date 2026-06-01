import Foundation

// Distinct from `ConfigWriter`, which only overlays the mutable
// `workflows`/`models` keys: this writes every base field ConfigWriter
// deliberately leaves alone, and the result must load through `ConfigLoader`.
nonisolated struct ProjectConfigCreator {
    let createdWithPlumageVersion: String
    let minPlumageVersion: String
    let issueIdPadding: Int

    init(
        createdWithPlumageVersion: String = ProjectConfigCreator.bundleVersion,
        minPlumageVersion: String = "0.1.0",
        issueIdPadding: Int = 5
    ) {
        self.createdWithPlumageVersion = createdWithPlumageVersion
        self.minPlumageVersion = minPlumageVersion
        self.issueIdPadding = issueIdPadding
    }

    static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    func makeConfigData(for spec: NewProjectSpec, defaultBranch: String = "main") throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(makeConfig(for: spec, defaultBranch: defaultBranch))
    }

    func write(for spec: NewProjectSpec, toBundle bundle: URL, defaultBranch: String = "main") throws {
        try makeConfigData(for: spec, defaultBranch: defaultBranch)
            .write(to: bundle.appending(path: "config.json"))
    }

    private func makeConfig(for spec: NewProjectSpec, defaultBranch: String) -> FullConfig {
        let profile = spec.kind.profile
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return FullConfig(
            agentTimeouts: .init(planModeProbeMs: 5000),
            createdAt: timestamp,
            createdWithPlumageVersion: createdWithPlumageVersion,
            git: .init(
                agentFilesInGit: spec.git?.claudeInGit ?? true,
                branchPrefix: "issue/",
                defaultBranch: defaultBranch),
            issueIdPadding: issueIdPadding,
            minPlumageVersion: minPlumageVersion,
            name: spec.name,
            paths: .init(archive: ".claude/issues/archive", issues: ".claude/issues"),
            plumageManaged: .init(
                mcps: profile.mcpServers.map {
                    .init(configHash: "initial", name: $0.name, scope: "project", version: "latest")
                },
                skills: ["plumage-plan", "plumage-implement", "plumage-review"].map {
                    .init(initialHash: "initial", name: $0, source: "plumage-builtin")
                },
                snippets: profile.templateLayers.map {
                    .init(initialHash: "initial", name: $0, version: "0.1.0")
                }),
            projectType: spec.kind.rawValue,
            schemaVersion: SchemaVersion.current,
            workflows: .init(
                implement: .init(command: nil, permissionMode: "auto"),
                plan: .init(command: "/plumage-plan <slug> - <prompt>\n", permissionMode: nil),
                review: .init(command: nil, permissionMode: "auto")))
    }
}

private nonisolated struct FullConfig: Encodable {
    let agentTimeouts: AgentTimeouts
    let createdAt: String
    let createdWithPlumageVersion: String
    let git: GitSection
    let issueIdPadding: Int
    let minPlumageVersion: String
    let name: String
    let paths: Paths
    let plumageManaged: PlumageManaged
    let projectType: String
    let schemaVersion: Int
    let workflows: Workflows

    struct AgentTimeouts: Encodable { let planModeProbeMs: Int }
    struct GitSection: Encodable {
        let agentFilesInGit: Bool
        let branchPrefix: String
        let defaultBranch: String
    }
    struct Paths: Encodable {
        let archive: String
        let issues: String
    }
    struct PlumageManaged: Encodable {
        let mcps: [MCP]
        let skills: [SkillEntry]
        let snippets: [Snippet]
    }
    struct MCP: Encodable {
        let configHash: String
        let name: String
        let scope: String
        let version: String
    }
    struct SkillEntry: Encodable {
        let initialHash: String
        let name: String
        let source: String
    }
    struct Snippet: Encodable {
        let initialHash: String
        let name: String
        let version: String
    }
    struct Workflows: Encodable {
        let implement: Override
        let plan: Override
        let review: Override
    }
    struct Override: Encodable {
        let command: String?
        let permissionMode: String?
    }
}
