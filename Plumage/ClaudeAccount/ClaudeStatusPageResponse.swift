import Foundation

nonisolated enum ClaudeStatusIndicator: String, Sendable, Equatable, Codable {
    case none
    case minor
    case major
    case critical
    case maintenance
    case unknown

    static func parse(_ raw: String?) -> ClaudeStatusIndicator {
        guard let raw, let mapped = ClaudeStatusIndicator(rawValue: raw.lowercased()) else {
            return .unknown
        }
        return mapped
    }

    var isOperational: Bool { self == .none }
}

nonisolated struct ClaudeStatusPageResponse: Sendable, Equatable, Decodable {
    let indicator: ClaudeStatusIndicator
    let description: String
    let component: Component?
    let incidents: [Incident]
    let updatedAt: Date?

    struct Component: Sendable, Equatable, Decodable {
        let name: String
        let status: String
    }

    struct Incident: Sendable, Equatable, Decodable {
        let name: String
        let status: String
        let impact: String
    }

    static func decode(data: Data) throws -> ClaudeStatusPageResponse {
        let envelope = try JSONDecoder.statusPageDecoder.decode(Envelope.self, from: data)
        let claudeCode = envelope.components?.first { $0.name == "Claude Code" }
        let component = claudeCode.map {
            Component(name: $0.name, status: $0.status)
        }
        let incidents =
            envelope.incidents?
            .map {
                Incident(name: $0.name, status: $0.status, impact: $0.impact)
            } ?? []
        return ClaudeStatusPageResponse(
            indicator: ClaudeStatusIndicator.parse(envelope.status?.indicator),
            description: envelope.status?.description ?? "Unknown status",
            component: component,
            incidents: incidents,
            updatedAt: envelope.page?.updatedAt
        )
    }

    private struct Envelope: Decodable {
        let page: Page?
        let status: Status?
        let components: [ComponentBody]?
        let incidents: [IncidentBody]?
    }

    private struct Page: Decodable {
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case updatedAt = "updated_at"
        }
    }

    private struct Status: Decodable {
        let indicator: String?
        let description: String?
    }

    private struct ComponentBody: Decodable {
        let name: String
        let status: String
    }

    private struct IncidentBody: Decodable {
        let name: String
        let status: String
        let impact: String
    }
}

nonisolated extension JSONDecoder {
    // ISO8601DateFormatter is not Sendable, so we construct it per call inside
    // the @Sendable strategy closure — notes.md 2026-05-13 (#00008-spec-editor
    // Code-Review) settled on this pattern after the cached-formatter rollback.
    fileprivate static var statusPageDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let primary = ISO8601DateFormatter()
            primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = primary.date(from: raw) { return date }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unparseable ISO-8601 date: \(raw)")
        }
        return decoder
    }
}
