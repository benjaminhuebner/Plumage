import Foundation
import Testing

@testable import Plumage

// Returns the queued bodies in order, all with HTTP 200 (the device-flow token
// endpoint returns 200 even for authorization_pending / slow_down).
private final class QueuedHTTPFetcher: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [Data]
    private(set) var callCount = 0

    init(_ bodies: [Data]) { self.bodies = bodies }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body: Data = lock.withLock {
            callCount += 1
            return bodies.isEmpty ? Data() : bodies.removeFirst()
        }
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else { throw URLError(.badServerResponse) }
        return (body, response)
    }
}

private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int] = []

    func record(_ seconds: Int) { lock.withLock { recorded.append(seconds) } }
    var values: [Int] { lock.withLock { recorded } }
}

@Suite("GitHubDeviceFlowClient")
struct GitHubDeviceFlowClientTests {
    private static let deviceCodeJSON = Data(
        """
        {"device_code":"dc123","user_code":"WXYZ-1234",
         "verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
        """.utf8)

    private func json(_ string: String) -> Data { Data(string.utf8) }

    private func client(_ fetcher: any HTTPFetching) -> GitHubDeviceFlowClient {
        GitHubDeviceFlowClient(fetcher: fetcher, clientID: "test-client", sleep: { _ in })
    }

    @Test("requestDeviceCode parses the user code and verification URL")
    func requestDeviceCode() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(
            .response(status: 200, body: Self.deviceCodeJSON), for: GitHubDeviceFlowClient.deviceCodeURL)
        let code = try await client(stub).requestDeviceCode(scope: "repo")
        #expect(code.deviceCode == "dc123")
        #expect(code.userCode == "WXYZ-1234")
        #expect(code.verificationURL == URL(string: "https://github.com/login/device"))
        #expect(code.interval == 5)
    }

    @Test("requestDeviceCode surfaces a non-200 as serverError")
    func requestDeviceCodeServerError() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 404, body: Data()), for: GitHubDeviceFlowClient.deviceCodeURL)
        await #expect(throws: GitHubDeviceFlowError.serverError(404)) {
            try await client(stub).requestDeviceCode(scope: "repo")
        }
    }

    @Test("pollForToken returns the token after authorization_pending rounds")
    func pollPendingThenToken() async throws {
        let fetcher = QueuedHTTPFetcher([
            json(#"{"error":"authorization_pending"}"#),
            json(#"{"error":"authorization_pending"}"#),
            json(#"{"access_token":"gho_abc","token_type":"bearer","scope":"repo"}"#),
        ])
        let token = try await client(fetcher).pollForToken(deviceCode: "dc123", interval: 5)
        #expect(token == "gho_abc")
        #expect(fetcher.callCount == 3)
    }

    @Test("pollForToken honors slow_down and still succeeds")
    func pollSlowDownThenToken() async throws {
        let fetcher = QueuedHTTPFetcher([
            json(#"{"error":"slow_down","interval":10}"#),
            json(#"{"access_token":"gho_xyz"}"#),
        ])
        let token = try await client(fetcher).pollForToken(deviceCode: "dc123", interval: 5)
        #expect(token == "gho_xyz")
    }

    @Test("a slow_down carrying interval 0 is floored so the poll keeps a delay")
    func slowDownZeroIntervalIsFloored() async throws {
        let fetcher = QueuedHTTPFetcher([
            json(#"{"error":"slow_down","interval":0}"#),
            json(#"{"access_token":"gho_ok"}"#),
        ])
        let recorder = SleepRecorder()
        let client = GitHubDeviceFlowClient(
            fetcher: fetcher, clientID: "test-client", sleep: { recorder.record($0) })
        let token = try await client.pollForToken(deviceCode: "dc123", interval: 5)
        #expect(token == "gho_ok")
        #expect(recorder.values.allSatisfy { $0 >= 1 })
    }

    @Test("pollForToken throws on access_denied")
    func pollAccessDenied() async {
        let fetcher = QueuedHTTPFetcher([json(#"{"error":"access_denied"}"#)])
        await #expect(throws: GitHubDeviceFlowError.accessDenied) {
            try await client(fetcher).pollForToken(deviceCode: "dc123", interval: 5)
        }
    }

    @Test("pollForToken throws on expired_token")
    func pollExpired() async {
        let fetcher = QueuedHTTPFetcher([json(#"{"error":"expired_token"}"#)])
        await #expect(throws: GitHubDeviceFlowError.expired) {
            try await client(fetcher).pollForToken(deviceCode: "dc123", interval: 5)
        }
    }
}
