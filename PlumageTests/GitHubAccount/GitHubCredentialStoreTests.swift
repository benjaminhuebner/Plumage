import Foundation
import Testing

@testable import Plumage

// Hits the real data-protection keychain. Isolated to a per-test random service
// so it never touches a user's real "Plumage GitHub" items and always cleans up.
@Suite("GitHubCredentialStore (keychain round-trip)")
struct GitHubCredentialStoreTests {
    private func makeStore() -> (store: ProductionGitHubCredentialStore, login: String, host: String) {
        let service = "Plumage GitHub Test \(UUID().uuidString)"
        let login = "octocat-\(UUID().uuidString)"
        return (ProductionGitHubCredentialStore(service: service), login, "github.com")
    }

    @Test("Save then read returns the stored token")
    func saveReadRoundTrip() throws {
        let (store, login, host) = makeStore()
        defer { try? store.deleteToken(login: login, host: host) }
        try store.saveToken("ghp_secret123", login: login, host: host)
        #expect(try store.readToken(login: login, host: host) == "ghp_secret123")
    }

    @Test("Saving again updates the token in place")
    func saveUpdatesInPlace() throws {
        let (store, login, host) = makeStore()
        defer { try? store.deleteToken(login: login, host: host) }
        try store.saveToken("first-token", login: login, host: host)
        try store.saveToken("second-token", login: login, host: host)
        #expect(try store.readToken(login: login, host: host) == "second-token")
    }

    @Test("Reading a missing item returns nil, not an error")
    func readMissingReturnsNil() throws {
        let (store, login, host) = makeStore()
        #expect(try store.readToken(login: login, host: host) == nil)
    }

    @Test("Delete removes the token")
    func deleteRemovesToken() throws {
        let (store, login, host) = makeStore()
        try store.saveToken("to-be-deleted", login: login, host: host)
        try store.deleteToken(login: login, host: host)
        #expect(try store.readToken(login: login, host: host) == nil)
    }

    @Test("Deleting a missing item is a no-op")
    func deleteMissingIsNoOp() throws {
        let (store, login, host) = makeStore()
        try store.deleteToken(login: login, host: host)
    }

    @Test("Two logins under the same service are independent")
    func distinctAccountsAreIndependent() throws {
        let service = "Plumage GitHub Test \(UUID().uuidString)"
        let store = ProductionGitHubCredentialStore(service: service)
        defer {
            try? store.deleteToken(login: "alice", host: "github.com")
            try? store.deleteToken(login: "bob", host: "github.com")
        }
        try store.saveToken("alice-token", login: "alice", host: "github.com")
        try store.saveToken("bob-token", login: "bob", host: "github.com")
        #expect(try store.readToken(login: "alice", host: "github.com") == "alice-token")
        #expect(try store.readToken(login: "bob", host: "github.com") == "bob-token")
    }
}
