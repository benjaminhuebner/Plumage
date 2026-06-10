import Foundation
import Testing

@testable import Plumage

@Suite("Tolerant enum decoding")
struct EnumDecodeFallbackTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test("unknown IssueStatus raw value coerces to .draft instead of failing")
    func issueStatusFallback() throws {
        #expect(try decode([IssueStatus].self, #"["future-state"]"#) == [.draft])
        #expect(try decode([IssueStatus].self, #"["in-progress"]"#) == [.inProgress])
    }

    @Test("unknown IssueType raw value coerces to .chore instead of failing")
    func issueTypeFallback() throws {
        #expect(try decode([IssueType].self, #"["epic"]"#) == [.chore])
        #expect(try decode([IssueType].self, #"["spike"]"#) == [.spike])
    }

    @Test("unknown permissionMode in a workflow override decodes as nil, not a coerced mode")
    func workflowOverridePermissionModeFallback() throws {
        let unknown = try decode(WorkflowOverride.self, #"{"permissionMode":"yolo"}"#)
        #expect(unknown.permissionMode == nil)
        let known = try decode(WorkflowOverride.self, #"{"permissionMode":"acceptEdits"}"#)
        #expect(known.permissionMode == .acceptEdits)
    }
}
