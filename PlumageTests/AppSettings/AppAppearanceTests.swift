import AppKit
import Testing

@testable import Plumage

@Suite struct AppAppearanceTests {
    @Test(arguments: AppAppearance.allCases)
    func rawValueRoundTrips(_ appearance: AppAppearance) {
        #expect(AppAppearance(rawValue: appearance.rawValue) == appearance)
    }

    @Test func unknownRawValueIsNil() {
        #expect(AppAppearance(rawValue: "frobnicate") == nil)
    }

    @Test func unknownStoredValueFallsBackToSystem() {
        let stored: String? = "frobnicate"
        let resolved = stored.flatMap(AppAppearance.init(rawValue:)) ?? .system
        #expect(resolved == .system)
    }

    @Test func missingStoredValueFallsBackToSystem() {
        let stored: String? = nil
        let resolved = stored.flatMap(AppAppearance.init(rawValue:)) ?? .system
        #expect(resolved == .system)
    }

    @Test func nsAppearanceMapping() {
        #expect(AppAppearance.system.nsAppearance == nil)
        #expect(AppAppearance.light.nsAppearance?.name == .aqua)
        #expect(AppAppearance.dark.nsAppearance?.name == .darkAqua)
    }
}
