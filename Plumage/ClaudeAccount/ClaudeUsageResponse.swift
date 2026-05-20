import Foundation

nonisolated struct ClaudeUsageResponse: Sendable, Equatable {
    let fiveHour: WindowUsage?
    let sevenDay: WindowUsage?
    let sevenDayOpus: WindowUsage?
    let extraSpendingUSD: Double?

    struct WindowUsage: Sendable, Equatable {
        let utilizationPct: Double
        let resetsAt: Date?
    }

    static func decode(data: Data) throws -> ClaudeUsageResponse {
        let envelope = try JSONDecoder.usageDecoder.decode(Envelope.self, from: data)
        return ClaudeUsageResponse(
            fiveHour: envelope.fiveHour?.toWindow(),
            sevenDay: envelope.sevenDay?.toWindow(),
            sevenDayOpus: envelope.sevenDayOpus?.toWindow(),
            extraSpendingUSD: envelope.extraUsage?.currentSpending
        )
    }

    private struct Envelope: Decodable {
        let fiveHour: WindowBody?
        let sevenDay: WindowBody?
        let sevenDayOpus: WindowBody?
        let extraUsage: ExtraUsage?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case extraUsage = "extra_usage"
        }
    }

    private struct WindowBody: Decodable {
        let utilizationPct: Double?
        let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilizationPct = "utilization_pct"
            case resetsAt = "resets_at"
        }

        func toWindow() -> WindowUsage? {
            guard let pct = utilizationPct else { return nil }
            return WindowUsage(utilizationPct: pct, resetsAt: resetsAt)
        }
    }

    private struct ExtraUsage: Decodable {
        let currentSpending: Double?

        enum CodingKeys: String, CodingKey {
            case currentSpending = "current_spending"
        }
    }
}

nonisolated struct ClaudeOrganizationListing: Sendable, Equatable {
    let id: String
    let name: String?

    static func decode(data: Data) throws -> [ClaudeOrganizationListing] {
        let envelope = try JSONDecoder.usageDecoder.decode([OrgBody].self, from: data)
        return envelope.map { ClaudeOrganizationListing(id: $0.uuid, name: $0.name) }
    }

    private struct OrgBody: Decodable {
        let uuid: String
        let name: String?
    }
}

nonisolated extension JSONDecoder {
    fileprivate static var usageDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Anthropic mixes ISO-8601 strings and Unix-seconds doubles; the
            // shape varies per endpoint, so try both before giving up.
            if let raw = try? container.decode(String.self) {
                let primary = ISO8601DateFormatter()
                primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = primary.date(from: raw) { return date }
                let fallback = ISO8601DateFormatter()
                fallback.formatOptions = [.withInternetDateTime]
                if let date = fallback.date(from: raw) { return date }
            }
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unparseable usage timestamp")
        }
        return decoder
    }
}
