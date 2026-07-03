import Foundation

nonisolated enum ReviewFindingsStore {
    static func load(from url: URL) -> Result<ReviewFindings, ReviewFindingsParseError> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
        {
            return .success(.empty)
        } catch {
            return .failure(.unreadable(message: error.localizedDescription))
        }
        return parse(data: data)
    }

    static func parse(data: Data) -> Result<ReviewFindings, ReviewFindingsParseError> {
        ISO8601JSONCodec.parse(ReviewFindings.self, from: data)
    }

    static func save(_ findings: ReviewFindings, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601Flexible.string(from: date))
        }
        let data = try encoder.encode(findings)
        try data.write(to: url, options: .atomic)
    }
}
