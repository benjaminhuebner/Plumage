import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeStatusPageClient")
struct ClaudeStatusPageClientTests {
    @Test("returns decoded status on 200")
    func returnsDecodedStatus() async throws {
        let stub = StubHTTPFetcher()
        let url = ClaudeStatusPageClient.summaryURL
        stub.setOutcome(.response(status: 200, body: Self.operationalBody), for: url)
        let client = ClaudeStatusPageClient(fetcher: stub, endpoint: url)
        let response = try await client.fetchStatus()
        #expect(response.indicator == .none)
        #expect(stub.requests.count == 1)
        #expect(stub.requests.first?.httpMethod == "GET")
    }

    @Test("maps 5xx to serverError")
    func mapsServerError() async {
        let stub = StubHTTPFetcher()
        stub.setDefault(.response(status: 503, body: Data()))
        let client = ClaudeStatusPageClient(fetcher: stub)
        await #expect(throws: ClaudeStatusPageError.serverError(503)) {
            _ = try await client.fetchStatus()
        }
    }

    @Test("maps transport failure")
    func mapsTransportFailure() async {
        let stub = StubHTTPFetcher()
        stub.setDefault(.failure(URLError(.notConnectedToInternet)))
        let client = ClaudeStatusPageClient(fetcher: stub)
        await #expect(throws: ClaudeStatusPageError.self) {
            _ = try await client.fetchStatus()
        }
    }

    @Test("maps decode failure to unparseable")
    func mapsDecodeFailure() async {
        let stub = StubHTTPFetcher()
        stub.setDefault(.response(status: 200, body: Data("not json".utf8)))
        let client = ClaudeStatusPageClient(fetcher: stub)
        await #expect(throws: ClaudeStatusPageError.self) {
            _ = try await client.fetchStatus()
        }
    }

    private static let operationalBody: Data = {
        let json = #"""
            {
              "status": { "indicator": "none", "description": "All Systems Operational" },
              "components": [{ "name": "Claude Code", "status": "operational" }],
              "incidents": []
            }
            """#
        return Data(json.utf8)
    }()
}
