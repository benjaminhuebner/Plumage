import Foundation
import Testing

@testable import Plumage

@Suite("DiffParser")
struct DiffParserTests {
    @Test("empty input returns empty array")
    func emptyInputReturnsEmptyArray() {
        let result = DiffParser.parse(unifiedDiff: "")
        #expect(result.isEmpty)
    }
}
