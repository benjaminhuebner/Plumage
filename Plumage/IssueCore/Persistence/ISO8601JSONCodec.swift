import Foundation

// evidence.json and review-findings.json share the same wire conventions:
// ISO-8601 dates and field-typed parse errors. Enum cases witness the
// static requirements, so both error enums keep their exact case surface.
nonisolated protocol FieldTypedParseError: Error {
    static func invalidJSON(message: String) -> Self
    static func missingRequiredField(name: String) -> Self
    static func invalidFieldValue(field: String, message: String) -> Self
}

nonisolated extension EvidenceParseError: FieldTypedParseError {}
nonisolated extension ReviewFindingsParseError: FieldTypedParseError {}

nonisolated enum ISO8601JSONCodec {
    static func parse<Value: Decodable, Failure: FieldTypedParseError>(
        _ type: Value.Type, from data: Data
    ) -> Result<Value, Failure> {
        do {
            return .success(try makeDecoder().decode(type, from: data))
        } catch let error as DecodingError {
            return .failure(map(error))
        } catch {
            return .failure(.invalidJSON(message: error.localizedDescription))
        }
    }

    private static func makeDecoder() -> JSONDecoder {
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
        return decoder
    }

    private static func map<Failure: FieldTypedParseError>(_ error: DecodingError) -> Failure {
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
