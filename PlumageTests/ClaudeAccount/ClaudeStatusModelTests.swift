import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("ClaudeStatusModel")
struct ClaudeStatusModelTests {
    @Test("loading → loaded on first refresh")
    func loadingToLoaded() async throws {
        let stub = StubHTTPFetcher()
        stub.setDefault(.response(status: 200, body: Self.operationalBody))
        let client = ClaudeStatusPageClient(fetcher: stub)
        let model = ClaudeStatusModel()
        await model.refresh(using: client)
        if case .loaded(let response) = model.state {
            #expect(response.indicator == .none)
        } else {
            Issue.record("expected .loaded, got \(model.state)")
        }
        #expect(model.lastRefreshedAt != nil)
    }

    @Test("loading → error when first refresh fails")
    func loadingToError() async {
        let stub = StubHTTPFetcher()
        stub.setDefault(.response(status: 503, body: Data()))
        let client = ClaudeStatusPageClient(fetcher: stub)
        let model = ClaudeStatusModel()
        await model.refresh(using: client)
        if case .error = model.state {
            // ok
        } else {
            Issue.record("expected .error, got \(model.state)")
        }
    }

    @Test("loaded state survives a later transport failure")
    func loadedSurvivesFailure() async {
        let stub = StubHTTPFetcher()
        stub.setDefault(.response(status: 200, body: Self.operationalBody))
        let client = ClaudeStatusPageClient(fetcher: stub)
        let model = ClaudeStatusModel()
        await model.refresh(using: client)

        stub.setDefault(.failure(URLError(.notConnectedToInternet)))
        await model.refresh(using: client)
        if case .loaded = model.state {
            // ok — last cache retained
        } else {
            Issue.record("expected loaded to be retained, got \(model.state)")
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
