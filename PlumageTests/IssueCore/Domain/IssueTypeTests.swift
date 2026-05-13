import SwiftUI
import Testing

@testable import Plumage

@Suite("IssueType")
struct IssueTypeTests {
    @Test("has exactly four cases")
    func allCasesCount() {
        #expect(IssueType.allCases.count == 4)
    }

    @Test("feature maps to green")
    func featureColor() {
        #expect(IssueType.feature.color == Color.green)
    }

    @Test("chore maps to yellow")
    func choreColor() {
        #expect(IssueType.chore.color == Color.yellow)
    }

    @Test("spike maps to orange")
    func spikeColor() {
        #expect(IssueType.spike.color == Color.orange)
    }

    @Test("refactor maps to cyan")
    func refactorColor() {
        #expect(IssueType.refactor.color == Color.cyan)
    }

    @Test("rawValue is lowercase case name")
    func rawValues() {
        #expect(IssueType.feature.rawValue == "feature")
        #expect(IssueType.chore.rawValue == "chore")
        #expect(IssueType.spike.rawValue == "spike")
        #expect(IssueType.refactor.rawValue == "refactor")
    }
}
