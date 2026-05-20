import Foundation

nonisolated struct ClaudeUsageResponse: Sendable, Equatable {
    let fiveHour: WindowUsage?
    let sevenDay: WindowUsage?
    let sevenDayOpus: WindowUsage?
    let sevenDaySonnet: WindowUsage?

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
            sevenDaySonnet: envelope.sevenDaySonnet?.toWindow()
        )
    }

    private struct Envelope: Decodable {
        let fiveHour: WindowBody?
        let sevenDay: WindowBody?
        let sevenDayOpus: WindowBody?
        let sevenDaySonnet: WindowBody?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDaySonnet = "seven_day_sonnet"
        }
    }

    private struct WindowBody: Decodable {
        let utilization: Double?
        let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        func toWindow() -> WindowUsage? {
            guard let pct = utilization else { return nil }
            return WindowUsage(utilizationPct: pct, resetsAt: resetsAt)
        }
    }
}

nonisolated extension JSONDecoder {
    fileprivate static var usageDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
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
