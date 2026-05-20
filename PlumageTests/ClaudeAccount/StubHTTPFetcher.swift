import Foundation

@testable import Plumage

// Minimal HTTP stub for ClaudeAccount client tests. @unchecked Sendable: state
// guarded by NSLock; same pattern as MockProcessRunner and MockXcodeProcessRunner.
final class StubHTTPFetcher: HTTPFetching, @unchecked Sendable {
    enum Outcome: Sendable {
        case response(status: Int, body: Data, headers: [String: String] = [:])
        case failure(URLError)
    }

    private let lock = NSLock()
    private var _outcomeByURL: [URL: Outcome] = [:]
    private var _defaultOutcome: Outcome = .response(status: 200, body: Data())
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    func setOutcome(_ outcome: Outcome, for url: URL) {
        lock.withLock { _outcomeByURL[url] = outcome }
    }

    func setDefault(_ outcome: Outcome) {
        lock.withLock { _defaultOutcome = outcome }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let outcome: Outcome = lock.withLock {
            _requests.append(request)
            if let url = request.url, let specific = _outcomeByURL[url] {
                return specific
            }
            return _defaultOutcome
        }
        switch outcome {
        case .response(let status, let body, let headers):
            guard let url = request.url else { throw URLError(.badURL) }
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
            guard let response else { throw URLError(.badServerResponse) }
            return (body, response)
        case .failure(let error):
            throw error
        }
    }
}
