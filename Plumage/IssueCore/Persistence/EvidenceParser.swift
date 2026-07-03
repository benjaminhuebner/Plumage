import Foundation

nonisolated enum EvidenceParser {
    static func parse(data: Data) -> Result<RunEvidence, EvidenceParseError> {
        ISO8601JSONCodec.parse(RunEvidence.self, from: data)
    }
}
