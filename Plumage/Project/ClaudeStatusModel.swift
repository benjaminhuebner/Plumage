import Foundation
import Observation

@Observable
@MainActor
final class ClaudeStatusModel {
    enum State: Sendable, Equatable {
        case loading
        case loaded(ClaudeStatusPageResponse)
        case error(String)
    }

    private(set) var state: State = .loading
    private(set) var lastRefreshedAt: Date?

    var indicator: ClaudeStatusIndicator {
        if case .loaded(let response) = state { return response.indicator }
        return .unknown
    }

    var description: String? {
        if case .loaded(let response) = state { return response.description }
        return nil
    }

    var incidents: [ClaudeStatusPageResponse.Incident] {
        if case .loaded(let response) = state { return response.incidents }
        return []
    }

    var component: ClaudeStatusPageResponse.Component? {
        if case .loaded(let response) = state { return response.component }
        return nil
    }

    // Never returns normally — loops until the caller's Task is cancelled
    // (parent .task(id:) re-fire or window close); Task.sleep is that point.
    func startPolling(using client: ClaudeStatusPageClient, interval: Duration = .seconds(60)) async {
        await refresh(using: client)
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            await refresh(using: client)
        }
    }

    func refresh(using client: ClaudeStatusPageClient) async {
        do {
            let response = try await client.fetchStatus()
            state = .loaded(response)
            lastRefreshedAt = Date()
        } catch is CancellationError {
            return
        } catch let error as ClaudeStatusPageError {
            // Keep the last loaded value visible (no state transition out of
            // .loaded) — only surface .error from .loading so the UI never
            // flickers between cached usage and a transient transport hiccup.
            if case .loading = state {
                state = .error(Self.message(for: error))
            }
        } catch {
            if case .loading = state {
                state = .error(error.localizedDescription)
            }
        }
    }

    nonisolated static func message(for error: ClaudeStatusPageError) -> String {
        switch error {
        case .transport(let detail): return "Network: \(detail)"
        case .unparseable(let detail): return "Unparseable response: \(detail)"
        case .serverError(let code): return "Server error \(code)"
        }
    }
}
