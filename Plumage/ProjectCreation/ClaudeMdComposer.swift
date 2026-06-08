import Foundation

// `CLAUDE.md` is composed by harvesting `%% keyword %%` blocks from every active layer
// (via `PlaceholderMerge`), inlining them into the base skeleton's `<<<keyword>>>`
// placeholders, substituting the scalar catalog/spec tokens, then dropping any
// placeholder no layer filled. Scalar tokens resolve after block inlining so they fill
// even inside an inlined block (e.g. the `<<<XCODE_MCP_LINE>>>` an Apple layer carries).
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
        let skeleton = try overrides.string(atRelative: "templates/CLAUDE.md")

        let contributions = try layers.map {
            try overrides.string(atRelative: ScaffoldOverrides.layerRelativePath($0))
        }
        let resolved = try PlaceholderMerge.resolvedBlocks(from: contributions)

        var result = PlaceholderMerge.inline(skeleton, resolved: resolved)
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

        return Output(claudeMd: result)
    }
}
