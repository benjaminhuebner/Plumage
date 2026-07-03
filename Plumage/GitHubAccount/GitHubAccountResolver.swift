import Foundation

nonisolated enum GitHubAccountResolver {
    // Only github.com today; multiple unbound accounts with no owner match fall
    // back to the most recently added.
    static func resolve(
        host: String?,
        owner: String?,
        accounts: [GitHubAccount],
        boundAccountID: String?
    ) -> GitHubAccount? {
        guard let host, host.lowercased() == GitHubAccount.defaultHost else { return nil }
        let sameHost = accounts.filter { $0.host.lowercased() == host.lowercased() }
        guard !sameHost.isEmpty else { return nil }

        if let boundAccountID, let bound = sameHost.first(where: { $0.id == boundAccountID }) {
            return bound
        }
        if sameHost.count == 1 { return sameHost.first }
        if let owner, let match = sameHost.first(where: { $0.login.lowercased() == owner.lowercased() }) {
            return match
        }
        return sameHost.max(by: { $0.addedAt < $1.addedAt })
    }
}
