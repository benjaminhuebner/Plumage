import AppKit
import Testing

@testable import Plumage

struct TerminalFontPreferenceTests {
    @Test func clampsToBounds() {
        #expect(TerminalFontPreference.clamped(1) == TerminalFontPreference.minSize)
        #expect(TerminalFontPreference.clamped(99) == TerminalFontPreference.maxSize)
        #expect(TerminalFontPreference.clamped(14) == 14)
    }

    @Test func stepsByOnePoint() {
        #expect(TerminalFontPreference.increased(from: 12) == 13)
        #expect(TerminalFontPreference.decreased(from: 12) == 11)
    }

    @Test func stepsSaturateAtBounds() {
        #expect(
            TerminalFontPreference.increased(from: TerminalFontPreference.maxSize)
                == TerminalFontPreference.maxSize)
        #expect(
            TerminalFontPreference.decreased(from: TerminalFontPreference.minSize)
                == TerminalFontPreference.minSize)
    }

    @Test func fontClampsOutOfRangeSizes() {
        let clampedSize = Double(TerminalFontPreference.font(ofSize: 999).pointSize)
        #expect(abs(clampedSize - TerminalFontPreference.maxSize) < 0.001)
        let normalSize = Double(TerminalFontPreference.font(ofSize: 12).pointSize)
        #expect(abs(normalSize - 12) < 0.001)
    }

    @Test func defaultSizeIsWithinBounds() {
        #expect(
            TerminalFontPreference.clamped(TerminalFontPreference.defaultSize)
                == TerminalFontPreference.defaultSize)
    }
}
