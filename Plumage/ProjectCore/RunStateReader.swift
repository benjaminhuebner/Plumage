import Foundation

nonisolated enum RunStateReader {
    enum ReadError: Error, Equatable, Sendable {
        case unreadable
        case malformed
    }

    static func read(at url: URL) throws -> RunState {
        guard let data = try? Data(contentsOf: url) else { throw ReadError.unreadable }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> RunState {
        guard let state = try? makeDecoder().decode(RunState.self, from: data) else {
            throw ReadError.malformed
        }
        return state
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601Flexible.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "not ISO-8601: \(raw)")
            }
            return date
        }
        return decoder
    }
}
