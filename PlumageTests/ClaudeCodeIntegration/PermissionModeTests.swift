import Testing

@testable import Plumage

@Suite("PermissionMode")
struct PermissionModeTests {
    @Test("rawCLIValue maps every case to the exact CLI string claude accepts")
    func rawCLIValues() {
        #expect(PermissionMode.plan.rawCLIValue == "plan")
        #expect(PermissionMode.acceptEdits.rawCLIValue == "acceptEdits")
        #expect(PermissionMode.auto.rawCLIValue == "auto")
        #expect(PermissionMode.bypassPermissions.rawCLIValue == "bypassPermissions")
        #expect(PermissionMode.default.rawCLIValue == "default")
        #expect(PermissionMode.dontAsk.rawCLIValue == "dontAsk")
    }

    @Test("allCases covers all six supported permission modes")
    func allCasesCount() {
        #expect(PermissionMode.allCases.count == 6)
        #expect(
            Set(PermissionMode.allCases) == [
                .plan, .acceptEdits, .auto, .bypassPermissions, .default, .dontAsk,
            ]
        )
    }
}
