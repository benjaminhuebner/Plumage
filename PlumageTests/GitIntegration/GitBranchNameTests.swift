import Testing

@testable import Plumage

@Suite("GitBranchName")
struct GitBranchNameTests {
    @Test(
        "accepts common branch names",
        arguments: [
            "main", "develop", "issue/00042-add-user-auth", "feature/foo-bar",
            "v1.2.3", "user_name/topic", "hotfix-2026",
        ])
    func acceptsValid(name: String) {
        #expect(GitBranchName.isSafe(name))
    }

    @Test(
        "rejects option-shaped and malformed names",
        arguments: [
            "", "-b", "--output=/tmp/x", "a b", "a\tb", "a\nb", "a..b", "a//b",
            "a@{1}", "/leading", ".hidden", "trailing/", "trailing.", "ref.lock",
            "a~b", "a^b", "a:b", "a?b", "a*b", "a[b", "a\\b",
        ])
    func rejectsUnsafe(name: String) {
        #expect(!GitBranchName.isSafe(name))
    }
}
