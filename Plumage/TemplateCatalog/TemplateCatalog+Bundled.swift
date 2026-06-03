import Foundation

// The predefined catalog, derived once from `ProjectKind` so the data model is a
// faithful re-representation of today's profiles. The shared components and their
// memberships are chosen so the effective resolver reproduces every kind's
// `ProjectKindProfile` byte-for-byte (pinned by tests).
nonisolated extension TemplateCatalog {
    static let bundledDefault: TemplateCatalog = makeBundledDefault()

    static func makeBundledDefault() -> TemplateCatalog {
        let base = BaseTemplate(
            id: "base",
            name: "Base",
            claudeMdRelativePath: "templates/CLAUDE.md",
            workflowHooks: ProjectKindProfile.workflowHooks
        )

        let categories = ProjectKindGroup.allCases.enumerated().map { index, group in
            TemplateCategory(id: group.rawValue, name: group.displayName, order: index)
        }

        let swiftKindIDs = Set(ProjectKind.allCases.filter(\.isSwift).map(\.rawValue))
        let appleKindIDs = Set([ProjectKind.appleMultiplatform, .macOS, .iOS].map(\.rawValue))
        // The 3 Swift tooling hooks = swiftHooks minus the always-present workflow hooks.
        let swiftToolingHooks = ProjectKindProfile.swiftHooks.filter {
            !ProjectKindProfile.workflowHooks.contains($0)
        }

        // Swift Shared carries both the shared CLAUDE.md layer and the Swift tooling
        // hooks — same membership (every Swift kind), so they live in one component.
        let sharedComponents = [
            SharedComponent(
                id: "swift-shared", name: "Swift Shared",
                files: [ComponentFile(kind: .layer, name: "swift-shared")]
                    + swiftToolingHooks.map { ComponentFile(kind: .hook, name: $0) },
                order: 0, memberTemplateIDs: swiftKindIDs),
            SharedComponent(
                id: "apple-shared", name: "Apple Shared",
                files: [ComponentFile(kind: .layer, name: "apple-shared")],
                order: 1, memberTemplateIDs: appleKindIDs),
        ]

        // Layer files contributed by shared components — stripped from each profile's
        // layer list to leave only the template-specific layer(s).
        let sharedLayerFiles = Set(sharedComponents.flatMap { $0.files(ofKind: .layer) })

        let templates = ProjectKind.allCases.enumerated().map { index, kind -> TemplateDescriptor in
            let profile = kind.profile
            return TemplateDescriptor(
                id: kind.rawValue,
                name: kind.displayName,
                image: .symbol(symbolName(for: kind)),
                categoryID: kind.group.rawValue,
                predefined: true,
                order: index,
                templateLayers: profile.templateLayers.filter { !sharedLayerFiles.contains($0) },
                gitignoreTags: profile.gitignoreTags,
                mcpServers: profile.mcpServers,
                gateCommands: profile.gateCommands,
                stackSummary: profile.stackSummary,
                xcodeMcpLine: profile.xcodeMcpLine
            )
        }

        return TemplateCatalog(
            base: base, categories: categories,
            sharedComponents: sharedComponents, templates: templates)
    }

    private static func symbolName(for kind: ProjectKind) -> String {
        switch kind {
        case .appleMultiplatform: "square.stack.3d.up"
        case .macOS: "macwindow"
        case .iOS: "iphone"
        case .vapor: "server.rack"
        case .hummingbird: "bird"
        case .swiftCLI: "terminal"
        case .other: "doc"
        }
    }
}
