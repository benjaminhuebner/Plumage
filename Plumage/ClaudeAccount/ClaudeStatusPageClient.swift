import Foundation

nonisolated enum ClaudeStatusPageError: Error, Sendable, Equatable {
    case transport(String)
    case unparseable(String)
    case serverError(Int)
}

nonisolated protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated extension HTTPFetching {
    // Shared plumbing for the ClaudeAccount pollers: cancellation (either
    // CancellationError or URLError.cancelled) surfaces as CancellationError,
    // other failures map through `transportError`, non-2xx through `statusError`.
    func successData(
        for request: URLRequest,
        transportError: (any Error) -> any Error,
        statusError: (Int) -> any Error
    ) async throws -> Data {
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await self.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw transportError(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw statusError(response.statusCode)
        }
        return data
    }
}

nonisolated struct ProductionHTTPFetcher: HTTPFetching {
    let session: URLSession

    // waitsForConnectivity lets the system batch the 60–90 s polls instead
    // of burning a wake per offline tick; the resource timeout bounds the
    // wait — its 7-day default would pin an offline poller inside one fetch.
    private static let connectivityWaitingSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
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
        let data = try await fetcher.successData(
            for: request,
            transportError: { error in
                // ProductionHTTPFetcher's own errors are already in domain shape.
                (error as? ClaudeStatusPageError)
                    ?? ClaudeStatusPageError.transport(error.localizedDescription)
            },
            statusError: { ClaudeStatusPageError.serverError($0) })
        do {
            return try ClaudeStatusPageResponse.decode(data: data)
        } catch {
            throw ClaudeStatusPageError.unparseable(error.localizedDescription)
        }
    }
}
