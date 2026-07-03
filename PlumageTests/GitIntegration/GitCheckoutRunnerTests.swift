import Foundation
import Testing

@testable import Plumage

struct GitCheckoutRunnerTests {
    private let repoURL = URL(filePath: "/tmp/repo")

    @Test("checkout runs git -C <repo> checkout <branch>")
    func checkoutRunsExpectedArgs() async throws {
        let mock = MockGitProcessRunner()
        let checkout = GitCheckoutRunner(
            runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })

        try await checkout.checkout(repoURL: repoURL, branch: "feature/extra")

        #expect(mock.recordedCalls == [["-C", "/tmp/repo", "checkout", "feature/extra"]])
    }

    @Test("createBranch runs git -C <repo> checkout -b <name>")
    func createBranchRunsExpectedArgs() async throws {
        let mock = MockGitProcessRunner()
        let checkout = GitCheckoutRunner(
            runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })

        try await checkout.createBranch(repoURL: repoURL, name: "feature/new")

        #expect(mock.recordedCalls == [["-C", "/tmp/repo", "checkout", "-b", "feature/new"]])
    }

    @Test(
        "unsafe branch names are rejected before git runs",
        arguments: ["", "-rf", "a..b", "bad name", "trailing/", "opt@{ref}"]
    )
    func unsafeNameThrowsWithoutRunning(name: String) async {
        let mock = MockGitProcessRunner()
        let checkout = GitCheckoutRunner(
            runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })

        await #expect(throws: GitCheckoutError.unsafeBranchName(name: name)) {
            try await checkout.checkout(repoURL: repoURL, branch: name)
        }
        await #expect(throws: GitCheckoutError.unsafeBranchName(name: name)) {
            try await checkout.createBranch(repoURL: repoURL, name: name)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("non-zero exit throws checkoutFailed with stderr")
    func nonZeroExitThrows() async {
        let mock = MockGitProcessRunner()
        let args = ["-C", "/tmp/repo", "checkout", "main"]
        mock.exitCodeForArgs = [args: 1]
        mock.stderrForArgs = [
            args: "error: Your local changes to the following files would be overwritten"
        ]
        let checkout = GitCheckoutRunner(
            runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })

        await #expect(
            throws: GitCheckoutError.checkoutFailed(
                stderr: "error: Your local changes to the following files would be overwritten")
        ) {
            try await checkout.checkout(repoURL: repoURL, branch: "main")
        }
    }

    @Test("missing git binary throws gitNotFound")
    func missingBinaryThrows() async {
        let checkout = GitCheckoutRunner(runner: MockGitProcessRunner(), resolveBinary: { nil })

        await #expect(throws: GitCheckoutError.gitNotFound) {
            try await checkout.checkout(repoURL: repoURL, branch: "main")
        }
    }
}
