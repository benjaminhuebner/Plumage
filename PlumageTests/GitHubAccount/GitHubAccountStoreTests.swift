import Foundation
import Testing

@testable import Plumage

@Suite("GitHubAccountStore")
struct GitHubAccountStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "github-accounts-\(UUID().uuidString).json")
    }

    private func sampleAccounts() -> [GitHubAccount] {
        [
            GitHubAccount(
                login: "octocat", host: "github.com", name: "The Octocat",
                avatarURL: URL(string: "https://avatars.example.com/octocat.png"),
                scopes: ["repo", "read:org"],
                addedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            GitHubAccount(
                login: "hubot", host: "github.com", name: nil,
                avatarURL: nil, scopes: [],
                addedAt: Date(timeIntervalSince1970: 1_700_000_100)),
        ]
    }

    @Test("Loading a missing file yields no accounts")
    func loadMissingReturnsEmpty() {
        let store = GitHubAccountStore(storeURL: tempURL())
        #expect(store.load().isEmpty)
    }

    @Test("Saved accounts survive a save/load round-trip")
    func saveLoadRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GitHubAccountStore(storeURL: url)
        let accounts = sampleAccounts()
        try store.save(accounts)
        #expect(store.load() == accounts)
    }

    @Test("A fresh store reading the same file sees the persisted accounts")
    func persistsAcrossInstances() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try GitHubAccountStore(storeURL: url).save(sampleAccounts())
        #expect(GitHubAccountStore(storeURL: url).load() == sampleAccounts())
    }

    @Test("Saving replaces the previous contents")
    func saveReplaces() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GitHubAccountStore(storeURL: url)
        try store.save(sampleAccounts())
        let single = [
            GitHubAccount(
                login: "solo", host: "github.com", name: nil, avatarURL: nil,
                scopes: [], addedAt: Date(timeIntervalSince1970: 1_700_000_200))
        ]
        try store.save(single)
        #expect(store.load().map(\.login) == ["solo"])
    }

    @Test("Account identity is login@host")
    func identityIsLoginAtHost() {
        let account = GitHubAccount(
            login: "octocat", host: "github.com", name: nil, avatarURL: nil,
            scopes: [], addedAt: Date(timeIntervalSince1970: 0))
        #expect(account.id == "octocat@github.com")
        #expect(GitHubAccount.identifier(login: "octocat", host: "github.com") == "octocat@github.com")
    }
}
