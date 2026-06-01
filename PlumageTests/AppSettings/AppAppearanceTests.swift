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
        #expect(AppAppearance.resolve(from: "frobnicate") == .system)
    }

    @Test func missingStoredValueFallsBackToSystem() {
        #expect(AppAppearance.resolve(from: nil) == .system)
    }

    @Test(arguments: AppAppearance.allCases)
    func storedValueResolvesToMatchingCase(_ appearance: AppAppearance) {
        #expect(AppAppearance.resolve(from: appearance.rawValue) == appearance)
    }

    @Test func nsAppearanceMapping() {
        #expect(AppAppearance.system.nsAppearance == nil)
        #expect(AppAppearance.light.nsAppearance?.name == .aqua)
        #expect(AppAppearance.dark.nsAppearance?.name == .darkAqua)
    }
}
