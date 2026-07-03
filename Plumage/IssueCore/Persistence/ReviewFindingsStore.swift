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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ISO8601Flexible.date(from: string) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid ISO-8601 date: \(string)"
                    )
                )
            }
            return date
        }
        do {
            return .success(try decoder.decode(ReviewFindings.self, from: data))
        } catch let error as DecodingError {
            return .failure(map(error))
        } catch {
            return .failure(.invalidJSON(message: error.localizedDescription))
        }
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

    private static func map(_ error: DecodingError) -> ReviewFindingsParseError {
        switch error {
        case .keyNotFound(let key, _):
            .missingRequiredField(name: key.stringValue)
        case .valueNotFound(_, let context):
            .missingRequiredField(name: context.codingPath.last?.stringValue ?? "(unknown)")
        case .typeMismatch(_, let context):
            .invalidFieldValue(
                field: context.codingPath.last?.stringValue ?? "(unknown)",
                message: context.debugDescription
            )
        case .dataCorrupted(let context):
            if let field = context.codingPath.last?.stringValue {
                .invalidFieldValue(field: field, message: context.debugDescription)
            } else {
                .invalidJSON(message: context.debugDescription)
            }
        @unknown default:
            .invalidJSON(message: error.localizedDescription)
        }
    }
}
