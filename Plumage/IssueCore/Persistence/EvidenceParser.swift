import Foundation

nonisolated enum EvidenceParser {
    static func parse(data: Data) -> Result<RunEvidence, EvidenceParseError> {
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
            return .success(try decoder.decode(RunEvidence.self, from: data))
        } catch let error as DecodingError {
            return .failure(map(error))
        } catch {
            return .failure(.invalidJSON(message: error.localizedDescription))
        }
    }

    private static func map(_ error: DecodingError) -> EvidenceParseError {
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
