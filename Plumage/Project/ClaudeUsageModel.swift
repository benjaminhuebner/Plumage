import Foundation
import Observation

@Observable
@MainActor
final class ClaudeUsageModel {
    enum State: Sendable, Equatable {
        case loading
        case loggedOut
        case error(String)
        case usage(ClaudeUsageResponse)
    }

    private(set) var state: State = .loading
    private(set) var lastRefreshedAt: Date?

    var isLoggedOut: Bool {
        if case .loggedOut = state { return true }
        return false
    }

    var fiveHour: ClaudeUsageResponse.WindowUsage? {
        if case .usage(let response) = state { return response.fiveHour }
        return nil
    }

    var sevenDay: ClaudeUsageResponse.WindowUsage? {
        if case .usage(let response) = state { return response.sevenDay }
        return nil
    }

    var sevenDayOpus: ClaudeUsageResponse.WindowUsage? {
        if case .usage(let response) = state { return response.sevenDayOpus }
        return nil
    }

    var sevenDaySonnet: ClaudeUsageResponse.WindowUsage? {
        if case .usage(let response) = state { return response.sevenDaySonnet }
        return nil
    }

    func refresh(using client: ClaudeUsageClient) async {
        do {
            let response = try await client.fetchUsage()
            state = .usage(response)
            lastRefreshedAt = Date()
        } catch is CancellationError {
            return
        } catch ClaudeUsageError.notLoggedIn {
            // Transition into loggedOut always wins so the UI swaps to the
            // LoggedOut hint immediately when the keychain item is removed.
            state = .loggedOut
        } catch let error as ClaudeUsageError {
            // Preserve any previously-loaded usage on transient errors. Only
            // surface the error string while still in .loading / .loggedOut.
            switch state {
            case .usage:
                return
            default:
                state = .error(Self.message(for: error))
            }
        } catch {
            if case .usage = state { return }
            state = .error(error.localizedDescription)
        }
    }

    static func message(for error: ClaudeUsageError) -> String {
        switch error {
        case .notLoggedIn: return "Not logged in"
        case .transport(let detail): return "Network: \(detail)"
        case .serverError(let code): return "Server error \(code)"
        case .unparseable(let detail): return "Unparseable response: \(detail)"
        }
    }
}
