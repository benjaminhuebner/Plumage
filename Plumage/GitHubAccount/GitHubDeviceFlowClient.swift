import Foundation

nonisolated struct GitHubDeviceCode: Sendable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let interval: Int
}

nonisolated enum GitHubDeviceFlowError: LocalizedError, Sendable, Equatable {
    case transport(String)
    case serverError(Int)
    case unparseable(String)
    case accessDenied
    case expired

    var errorDescription: String? {
        switch self {
        case .transport: "Couldn't reach GitHub. Check your connection."
        case .serverError(let code): "GitHub returned an error (HTTP \(code))."
        case .unparseable: "GitHub sign-in failed."
        case .accessDenied: "GitHub sign-in was denied."
        case .expired: "The sign-in code expired — try again."
        }
    }
}

// Secretless OAuth — only the public client_id, no client_secret. The poll step
// honors GitHub's authorization_pending / slow_down / expired_token contract.
nonisolated struct GitHubDeviceFlowClient: Sendable {
    static let deviceCodeURLString = "https://github.com/login/device/code"
    static let tokenURLString = "https://github.com/login/oauth/access_token"
    static let deviceCodeURL: URL = {
        guard let url = URL(string: deviceCodeURLString) else {
            preconditionFailure("invalid device-code URL literal")
        }
        return url
    }()
    static let tokenURL: URL = {
        guard let url = URL(string: tokenURLString) else {
            preconditionFailure("invalid token URL literal")
        }
        return url
    }()

    let fetcher: any HTTPFetching
    let clientID: String
    let deviceCodeEndpoint: URL
    let tokenEndpoint: URL
    let sleep: @Sendable (Int) async throws -> Void

    init(
        fetcher: any HTTPFetching = ProductionHTTPFetcher(),
        clientID: String = GitHubOAuthConfig.clientID,
        deviceCodeEndpoint: URL = GitHubDeviceFlowClient.deviceCodeURL,
        tokenEndpoint: URL = GitHubDeviceFlowClient.tokenURL,
        sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.fetcher = fetcher
        self.clientID = clientID
        self.deviceCodeEndpoint = deviceCodeEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.sleep = sleep
    }

    var isConfigured: Bool { !clientID.isEmpty }

    func requestDeviceCode(scope: String) async throws -> GitHubDeviceCode {
        let data = try await post(deviceCodeEndpoint, fields: ["client_id": clientID, "scope": scope])
        let body: DeviceCodeBody
        do {
            body = try JSONDecoder().decode(DeviceCodeBody.self, from: data)
        } catch {
            throw GitHubDeviceFlowError.unparseable(error.localizedDescription)
        }
        guard let url = URL(string: body.verificationURI) else {
            throw GitHubDeviceFlowError.unparseable("bad verification_uri")
        }
        return GitHubDeviceCode(
            deviceCode: body.deviceCode, userCode: body.userCode,
            verificationURL: url, interval: body.interval ?? 5)
    }

    // Cancellable via the injected sleep — Task.sleep throws CancellationError.
    func pollForToken(deviceCode: String, interval: Int) async throws -> String {
        var current = max(interval, 1)
        while true {
            try await sleep(current)
            switch try await requestToken(deviceCode: deviceCode) {
            case .token(let token): return token
            case .pending: continue
            // Keep the floor on every round — a stray interval of 0 must not
            // turn the poll into a delay-free hot loop against the endpoint.
            case .slowDown(let next): current = max(next ?? (current + 5), 1)
            case .denied: throw GitHubDeviceFlowError.accessDenied
            case .expired: throw GitHubDeviceFlowError.expired
            }
        }
    }

    private enum PollOutcome {
        case token(String)
        case pending
        case slowDown(Int?)
        case denied
        case expired
    }

    private func requestToken(deviceCode: String) async throws -> PollOutcome {
        let data = try await post(
            tokenEndpoint,
            fields: [
                "client_id": clientID, "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
        let body: TokenBody
        do {
            body = try JSONDecoder().decode(TokenBody.self, from: data)
        } catch {
            throw GitHubDeviceFlowError.unparseable(error.localizedDescription)
        }
        if let token = body.accessToken, !token.isEmpty { return .token(token) }
        switch body.error {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown(body.interval)
        case "access_denied": return .denied
        case "expired_token": return .expired
        default: throw GitHubDeviceFlowError.unparseable("unexpected token response")
        }
    }

    private func post(_ url: URL, fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await fetcher.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw GitHubDeviceFlowError.transport(error.localizedDescription)
        }
        guard response.statusCode == 200 else {
            throw GitHubDeviceFlowError.serverError(response.statusCode)
        }
        return data
    }

    static func formEncode(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private struct DeviceCodeBody: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationURI: String
        let interval: Int?

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case interval
        }
    }

    private struct TokenBody: Decodable {
        let accessToken: String?
        let error: String?
        let interval: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case error, interval
        }
    }
}
