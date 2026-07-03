import Foundation
import Testing

@testable import Plumage

@Suite("GitHubAccountResolver")
struct GitHubAccountResolverTests {
    private func account(_ login: String, addedAt: TimeInterval, host: String = "github.com") -> GitHubAccount {
        GitHubAccount(
            login: login, host: host, name: nil, avatarURL: nil, scopes: [],
            addedAt: Date(timeIntervalSince1970: addedAt))
    }

    @Test("a non-github host resolves to nil")
    func nonGithubHost() {
        let resolved = GitHubAccountResolver.resolve(
            host: "gitlab.com", owner: "x", accounts: [account("a", addedAt: 1)], boundAccountID: nil)
        #expect(resolved == nil)
    }

    @Test("a nil host resolves to nil")
    func nilHost() {
        let resolved = GitHubAccountResolver.resolve(
            host: nil, owner: "x", accounts: [account("a", addedAt: 1)], boundAccountID: nil)
        #expect(resolved == nil)
    }

    @Test("no accounts resolves to nil")
    func noAccounts() {
        let resolved = GitHubAccountResolver.resolve(
            host: "github.com", owner: "x", accounts: [], boundAccountID: nil)
        #expect(resolved == nil)
    }

    @Test("a single account is chosen regardless of the owner")
    func singleAccount() {
        let resolved = GitHubAccountResolver.resolve(
            host: "github.com", owner: "some-org", accounts: [account("alice", addedAt: 1)],
            boundAccountID: nil)
        #expect(resolved?.login == "alice")
    }

    @Test("a bound account wins over an owner match")
    func boundWins() {
        let accounts = [account("alice", addedAt: 1), account("bob", addedAt: 2)]
        let resolved = GitHubAccountResolver.resolve(
            host: "github.com", owner: "bob", accounts: accounts, boundAccountID: "alice@github.com")
        #expect(resolved?.login == "alice")
    }

    @Test("an owner match wins among multiple unbound accounts, case-insensitively")
    func ownerMatch() {
        let accounts = [account("alice", addedAt: 1), account("bob", addedAt: 2)]
        let resolved = GitHubAccountResolver.resolve(
            host: "github.com", owner: "BOB", accounts: accounts, boundAccountID: nil)
        #expect(resolved?.login == "bob")
    }

    @Test("ambiguous multiple accounts fall back to the most recently added")
    func ambiguousFallsBackToNewest() {
        let accounts = [account("alice", addedAt: 1), account("bob", addedAt: 5)]
        let resolved = GitHubAccountResolver.resolve(
            host: "github.com", owner: "some-org", accounts: accounts, boundAccountID: nil)
        #expect(resolved?.login == "bob")
    }

    @Test("a stale bound id falls through to the owner match")
    func staleBoundFallsThrough() {
        let accounts = [account("alice", addedAt: 1), account("bob", addedAt: 2)]
        let resolved = GitHubAccountResolver.resolve(
            host: "github.com", owner: "bob", accounts: accounts, boundAccountID: "ghost@github.com")
        #expect(resolved?.login == "bob")
    }
}
