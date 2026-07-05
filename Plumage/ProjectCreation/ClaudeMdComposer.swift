import Foundation

// Composes CLAUDE.md by heading-merging the active layers into the base skeleton,
// then resolving scalar tokens (post-merge, so layer-carried tokens fill too) and
// dropping unfilled sections. Legacy-format overrides convert in memory first.
nonisolated struct ClaudeMdComposer {
    let overrides: ScaffoldOverrides
    // The resolved catalog supplies the effective layer list and scalar tokens.
    // Defaults to the bundled catalog, which reproduces `ProjectKind.profile` exactly.
    var catalog: TemplateCatalog = .bundledDefault

    nonisolated struct Output: Hashable, Sendable {
        let claudeMd: String
    }

    func compose(spec: NewProjectSpec) throws -> Output {
        let templateID = spec.templateID
        let layers = catalog.effectiveLayers(forTemplate: templateID)
        let skeletonRaw = try overrides.string(atRelative: "templates/CLAUDE.md")
        let contributionsRaw = try layers.map {
            try overrides.string(atRelative: ScaffoldOverrides.layerRelativePath($0))
        }

        // Legacy pass: blocks still fill `<<<keyword>>>` lines of an unmigrated
        // skeleton override (custom keywords have no heading mapping); consumed
        // blocks stay out of the heading merge so their content can't land twice.
        let resolved = try PlaceholderMerge.resolvedBlocks(from: contributionsRaw)
        let consumed = PlaceholderMerge.placeholderKeywords(in: skeletonRaw)
            .intersection(resolved.keys)
        let headings = TemplateLayerFormatMigration.headings(forSkeleton: skeletonRaw)
        let skeleton = TemplateLayerFormatMigration.strippingSectionPlaceholders(
            from: PlaceholderMerge.inline(skeletonRaw, resolved: resolved))
        let contributions = contributionsRaw.map {
            TemplateLayerFormatMigration.headingSections(
                from: $0, excluding: consumed, headings: headings)
        }

        var result = MarkdownSectionMerge.merge(variants: [skeleton] + contributions)
        result =
            result
            .replacingOccurrences(of: "<<<PROJECT_NAME>>>", with: spec.name)
            .replacingOccurrences(of: "<<<PROJECT_TAGLINE>>>", with: spec.tagline)
            .replacingOccurrences(
                of: "<<<STACK_SUMMARY>>>",
                with: catalog.effectiveStackSummary(forTemplate: templateID)
            )
            .replacingOccurrences(
                of: "<<<XCODE_MCP_LINE>>>",
                with: catalog.effectiveXcodeMcpLine(forTemplate: templateID)
            )
        result = PlaceholderMerge.dropUnresolved(result)
        result = MarkdownSectionMerge.droppingEmptySections(result)

        return Output(claudeMd: result)
    }
}
