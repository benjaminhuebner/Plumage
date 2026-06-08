import Testing

@testable import Plumage

@Suite("PlaceholderMerge")
struct PlaceholderMergeTests {
    // MARK: - Block harvesting

    @Test("A closed block yields its trimmed body")
    func singleBlock() throws {
        let harvested = try PlaceholderMerge.blocks(in: "%% k %%\n- a\n- b\n%% /k %%")
        #expect(harvested.count == 1)
        #expect(harvested[0].keyword == "k")
        #expect(harvested[0].body == "- a\n- b")
    }

    @Test("Text outside any block is ignored")
    func ignoresFreeText() throws {
        let source = "preamble\n%% k %%\nbody\n%% /k %%\ntrailing junk"
        let harvested = try PlaceholderMerge.blocks(in: source)
        #expect(harvested.map(\.body) == ["body"])
    }

    @Test("An unclosed block is a validation error")
    func unclosedBlockThrows() {
        #expect(throws: PlaceholderMerge.MergeError.unclosedBlock(keyword: "k")) {
            try PlaceholderMerge.blocks(in: "%% k %%\nbody, no close")
        }
    }

    @Test("A new open before the previous close is an unclosed-block error")
    func reopenWithoutCloseThrows() {
        #expect(throws: PlaceholderMerge.MergeError.unclosedBlock(keyword: "a")) {
            try PlaceholderMerge.blocks(in: "%% a %%\nbody\n%% b %%\nmore\n%% /b %%")
        }
    }

    @Test("A close with no matching open is a dangling-close error")
    func danglingCloseThrows() {
        #expect(throws: PlaceholderMerge.MergeError.danglingClose(keyword: "k")) {
            try PlaceholderMerge.blocks(in: "%% /k %%")
        }
    }

    @Test("A close naming a different keyword than the open block throws")
    func mismatchedCloseThrows() {
        #expect(throws: PlaceholderMerge.MergeError.danglingClose(keyword: "b")) {
            try PlaceholderMerge.blocks(in: "%% a %%\nbody\n%% /b %%")
        }
    }

    // MARK: - Resolution & joining

    @Test("Same-keyword blocks across contributions join in order with a blank line")
    func multiBlockJoin() throws {
        let resolved = try PlaceholderMerge.resolvedBlocks(from: [
            "%% k %%\nfirst\n%% /k %%",
            "%% k %%\nsecond\n%% /k %%",
        ])
        #expect(resolved["k"] == "first\n\nsecond")
    }

    @Test("Empty-body blocks add no content and no stray separator")
    func emptyBodiesDropped() throws {
        let resolved = try PlaceholderMerge.resolvedBlocks(from: [
            "%% k %%\n%% /k %%",
            "%% k %%\nonly\n%% /k %%",
        ])
        #expect(resolved["k"] == "only")
    }

    // MARK: - Inlining & cleanup

    @Test("Arbitrary keywords inline at their placeholder, alone on a line")
    func arbitraryKeywordInlines() {
        let skeleton = "## Top\n<<<foo>>>\n## End"
        let out = PlaceholderMerge.inline(skeleton, resolved: ["foo": "filled"])
        #expect(out == "## Top\nfilled\n## End")
    }

    @Test("An indented or surrounded placeholder still matches its keyword")
    func placeholderWhitespaceTolerant() {
        #expect(PlaceholderMerge.inline("  <<< foo >>>  ", resolved: ["foo": "x"]) == "x")
    }

    @Test("An unfilled placeholder drops its line and the preceding heading")
    func dropUnresolvedRemovesHeading() {
        let text = "## Keep\nbody\n## Gone\n<<<missing>>>\n## After"
        #expect(PlaceholderMerge.dropUnresolved(text) == "## Keep\nbody\n## After")
    }

    @Test("hasPlaceholders detects an alone-on-a-line token, ignores inline ones")
    func detectsPlaceholders() {
        #expect(PlaceholderMerge.hasPlaceholders("a\n<<<x>>>\nb"))
        #expect(!PlaceholderMerge.hasPlaceholders("# <<<x>>> title"))
        #expect(!PlaceholderMerge.hasPlaceholders("plain text"))
    }

    @Test("merge composes a skeleton with contributions and drops the rest")
    func endToEndMerge() throws {
        let skeleton = "# Title\n\n## One\n<<<one>>>\n\n## Two\n<<<two>>>\n"
        let merged = try PlaceholderMerge.merge(
            skeleton: skeleton, contributions: ["%% one %%\nalpha\n%% /one %%"])
        // `two` has no contribution, so its heading and placeholder line drop out.
        #expect(merged == "# Title\n\n## One\nalpha\n")
    }

    // MARK: - Tolerant harvesting (legacy open-only layers, stray markers)

    @Test("Tolerant blocks auto-close a legacy open-only block at the next open and at EOF")
    func tolerantAutoCloses() throws {
        let legacy = "%% CONVENTIONS %%\n- a\n%% PITFALLS %%\n- b"
        let harvested = try PlaceholderMerge.blocks(in: legacy, tolerant: true)
        #expect(harvested.map(\.keyword) == ["CONVENTIONS", "PITFALLS"])
        #expect(harvested.map(\.body) == ["- a", "- b"])
    }

    @Test("resolvedBlocks recovers a legacy open-only contribution instead of throwing")
    func resolvedBlocksTolerantOfLegacy() throws {
        let resolved = try PlaceholderMerge.resolvedBlocks(from: [
            "%% CONVENTIONS %%\n- keep me\n%% PITFALLS %%\n- and me"
        ])
        #expect(resolved["CONVENTIONS"] == "- keep me")
        #expect(resolved["PITFALLS"] == "- and me")
    }

    @Test("A stray %% marker line in body no longer aborts the whole merge")
    func strayMarkerDoesNotAbort() throws {
        let merged = try PlaceholderMerge.merge(
            skeleton: "## One\n<<<one>>>\n",
            contributions: ["%% one %%\nreal\n%% stray %%\n"])
        #expect(merged.contains("real"))
    }

    @Test("Strict blocks still throw on a legacy open-only block (validation primitive)")
    func strictStillThrows() {
        #expect(throws: PlaceholderMerge.MergeError.unclosedBlock(keyword: "CONVENTIONS")) {
            try PlaceholderMerge.blocks(in: "%% CONVENTIONS %%\n- a\n%% PITFALLS %%\n- b")
        }
    }
}
