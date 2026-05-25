import Testing

@testable import Plumage

@Suite("PermissionMode")
struct PermissionModeTests {
    @Test("rawCLIValue maps every case to the exact CLI string claude accepts")
    func rawCLIValues() {
        #expect(PermissionMode.plan.rawCLIValue == "plan")
        #expect(PermissionMode.acceptEdits.rawCLIValue == "acceptEdits")
        #expect(PermissionMode.default.rawCLIValue == "default")
    }

    @Test("allCases covers the three supported workflow modes")
    func allCasesCount() {
        #expect(PermissionMode.allCases.count == 3)
        #expect(Set(PermissionMode.allCases) == [.plan, .acceptEdits, .default])
    }
}
