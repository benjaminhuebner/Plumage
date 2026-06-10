import Foundation

nonisolated enum ClaudeStatusPageError: Error, Sendable, Equatable {
    case transport(String)
    case unparseable(String)
    case serverError(Int)
}

nonisolated protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct ProductionHTTPFetcher: HTTPFetching {
    let session: URLSession

    // waitsForConnectivity: the pollers fire every 60–90 s for the app's
    // lifetime — failing fast on a sleeping radio just burns a wake plus an
    // error path per tick; waiting lets the system batch the request.
    private static let connectivityWaitingSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    init(session: URLSession = ProductionHTTPFetcher.connectivityWaitingSession) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeStatusPageError.transport("non-HTTP response")
        }
        return (data, http)
    }
}

nonisolated struct ClaudeStatusPageClient: Sendable {
    static let summaryURLString = "https://status.claude.com/api/v2/summary.json"
    static let summaryURL: URL = {
        guard let url = URL(string: summaryURLString) else {
            preconditionFailure("invalid status-page summary URL literal")
        }
        return url
    }()

    let fetcher: any HTTPFetching
    let endpoint: URL

    init(
        fetcher: any HTTPFetching = ProductionHTTPFetcher(),
        endpoint: URL = ClaudeStatusPageClient.summaryURL
    ) {
        self.fetcher = fetcher
        self.endpoint = endpoint
    }

    func fetchStatus() async throws -> ClaudeStatusPageResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await fetcher.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as ClaudeStatusPageError {
            throw error
        } catch {
            throw ClaudeStatusPageError.transport(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ClaudeStatusPageError.serverError(response.statusCode)
        }
        do {
            return try ClaudeStatusPageResponse.decode(data: data)
        } catch {
            throw ClaudeStatusPageError.unparseable(error.localizedDescription)
        }
    }
}
