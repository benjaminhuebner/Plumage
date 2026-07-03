import Testing

@testable import Plumage

@Suite("NavigatorRoute.rewritten")
struct NavigatorRouteRewriteTests {
    @Test("issue renamed in place re-points to the new folder")
    func issueRenamedInPlace() {
        let result = NavigatorRoute.rewritten(
            .issue(folderName: "00042-old"),
            by: [
                .moved(
                    oldRelativePath: ".claude/issues/00042-old",
                    newRelativePath: ".claude/issues/00042-new")
            ])
        #expect(result == .issue(folderName: "00042-new"))
    }

    @Test("externally removed issue falls back to the board")
    func issueRemovedFallsBackToBoard() {
        let result = NavigatorRoute.rewritten(
            .issue(folderName: "00042-old"),
            by: [.removed(oldRelativePath: ".claude/issues/00042-old")])
        #expect(result == .kanban)
    }

    @Test("issue moved out of the issues directory falls back to the board")
    func issueMovedOutFallsBackToBoard() {
        let result = NavigatorRoute.rewritten(
            .issue(folderName: "00042-old"),
            by: [
                .moved(
                    oldRelativePath: ".claude/issues/00042-old",
                    newRelativePath: "archive/00042-old")
            ])
        #expect(result == .kanban)
    }

    @Test("project file move re-points the selection")
    func fileMovedRepoints() {
        let result = NavigatorRoute.rewritten(
            .projectFile(relativePath: "docs/a.md"),
            by: [.moved(oldRelativePath: "docs/a.md", newRelativePath: "docs/b.md")])
        #expect(result == .projectFile(relativePath: "docs/b.md"))
    }

    @Test("project file under a moved folder re-points by suffix")
    func fileUnderMovedFolderRepoints() {
        let result = NavigatorRoute.rewritten(
            .projectFile(relativePath: "docs/sub/a.md"),
            by: [.moved(oldRelativePath: "docs", newRelativePath: "documents")])
        #expect(result == .projectFile(relativePath: "documents/sub/a.md"))
    }

    @Test("project file removal falls back to the board")
    func fileRemovedFallsBackToBoard() {
        let result = NavigatorRoute.rewritten(
            .projectFile(relativePath: "docs/a.md"),
            by: [.removed(oldRelativePath: "docs/a.md")])
        #expect(result == .kanban)
    }

    @Test("an unrelated rewrite leaves the route unchanged")
    func unrelatedRewriteReturnsNil() {
        let result = NavigatorRoute.rewritten(
            .issue(folderName: "00042-old"),
            by: [
                .moved(
                    oldRelativePath: ".claude/issues/00099-other",
                    newRelativePath: ".claude/issues/00099-renamed")
            ])
        #expect(result == nil)
    }

    @Test("board and settings routes are never rewritten")
    func boardAndSettingsUnaffected() {
        let rewrites: [RouteRewrite] = [.removed(oldRelativePath: ".claude/issues/00042-old")]
        #expect(NavigatorRoute.rewritten(.kanban, by: rewrites) == nil)
        #expect(NavigatorRoute.rewritten(.projectSettings, by: rewrites) == nil)
    }
}
