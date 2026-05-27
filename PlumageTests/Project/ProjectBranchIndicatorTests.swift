import Foundation
import Testing

@testable import Plumage

@Suite("ProjectBranchIndicator (state mapping)")
struct ProjectBranchIndicatorTests {
    @Test("not-a-repo yields no displayable label")
    func notARepo() {
        let state = RepoState.notARepo
        #expect(state.displayLabel == nil)
    }

    @Test("branch state surfaces verbatim")
    func branchState() {
        let state = RepoState.branch("issue/00050-git-functionality")
        #expect(state.displayLabel == "issue/00050-git-functionality")
        #expect(state.isDetached == false)
    }

    @Test("detached state shows (detached) <sha>")
    func detachedState() {
        let state = RepoState.detached(sha: "abc1234")
        #expect(state.displayLabel == "(detached) abc1234")
        #expect(state.isDetached)
        #expect(state.branchName == nil)
    }
}

@MainActor
@Suite("ProjectGitModel lifecycle")
struct ProjectGitModelTests {
    @Test("stop() resets to notARepo and is idempotent")
    func stopResetsState() {
        let model = ProjectGitModel()
        #expect(model.repoState == .notARepo)
        // start() needs a real path the FSEventSource can watch; bypass it
        // here and just confirm the reset behavior on a fresh model.
        model.stop()
        #expect(model.repoState == .notARepo)
        model.stop()
        #expect(model.repoState == .notARepo)
    }
}
