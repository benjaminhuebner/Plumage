import Foundation

@testable import Plumage

final class MockGitHubCredentialStore: GitHubCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    private var saveError: Error?
    private var readError: Error?
    private var deleteError: Error?
    private var deletedKeys: [String] = []

    func preset(_ token: String, login: String, host: String) {
        lock.withLock { storage[GitHubAccount.identifier(login: login, host: host)] = token }
    }

    func failSaves(with error: Error) { lock.withLock { saveError = error } }
    func failReads(with error: Error) { lock.withLock { readError = error } }
    func failDeletes(with error: Error) { lock.withLock { deleteError = error } }

    func storedToken(login: String, host: String) -> String? {
        lock.withLock { storage[GitHubAccount.identifier(login: login, host: host)] }
    }

    var deletions: [String] { lock.withLock { deletedKeys } }

    func saveToken(_ token: String, login: String, host: String) throws {
        try lock.withLock {
            if let saveError { throw saveError }
            storage[GitHubAccount.identifier(login: login, host: host)] = token
        }
    }

    func readToken(login: String, host: String) throws -> String? {
        try lock.withLock {
            if let readError { throw readError }
            return storage[GitHubAccount.identifier(login: login, host: host)]
        }
    }

    func deleteToken(login: String, host: String) throws {
        try lock.withLock {
            if let deleteError { throw deleteError }
            let key = GitHubAccount.identifier(login: login, host: host)
            deletedKeys.append(key)
            storage[key] = nil
        }
    }
}
