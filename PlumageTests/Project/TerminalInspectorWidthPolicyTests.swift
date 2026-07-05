import Foundation
import Testing

@testable import Plumage

struct TerminalInspectorWidthPolicyTests {
    @Test func wideWindowKeepsAbsoluteCap() {
        #expect(TerminalInspectorWidthPolicy.maxWidth(forContentWidth: 3000) == 900)
        #expect(TerminalInspectorWidthPolicy.minWidth(forContentWidth: 3000) == 360)
        #expect(TerminalInspectorWidthPolicy.idealWidth(forContentWidth: 3000) == 480)
    }

    @Test func reservesDetailAndSidebarSpaceUnconditionally() {
        // 1100 - 360 detail - 240 sidebar = 500 available, below the 605 fraction cap.
        // The reserve holds even with a hidden sidebar so a sidebar toggle
        // never forces the inspector column to resize.
        #expect(TerminalInspectorWidthPolicy.maxWidth(forContentWidth: 1100) == 500)
    }

    @Test func tinyWindowsFloorAtAbsoluteMin() {
        #expect(
            TerminalInspectorWidthPolicy.maxWidth(forContentWidth: 700)
                == TerminalInspectorWidthPolicy.absoluteMin)
        #expect(
            TerminalInspectorWidthPolicy.maxWidth(forContentWidth: 300)
                == TerminalInspectorWidthPolicy.absoluteMin)
    }

    @Test func rangeNeverInvertsAcrossWidths() {
        for width: CGFloat in [0, 100, 300, 500, 655, 800, 1000, 1200, 1636, 3000] {
            let minW = TerminalInspectorWidthPolicy.minWidth(forContentWidth: width)
            let ideal = TerminalInspectorWidthPolicy.idealWidth(forContentWidth: width)
            let maxW = TerminalInspectorWidthPolicy.maxWidth(forContentWidth: width)
            #expect(minW <= ideal, "min > ideal at width \(width)")
            #expect(ideal <= maxW, "ideal > max at width \(width)")
        }
    }

    @Test func unmeasuredWindowFallsBackToAbsoluteRange() {
        #expect(TerminalInspectorWidthPolicy.maxWidth(forContentWidth: 0) == 900)
        #expect(TerminalInspectorWidthPolicy.minWidth(forContentWidth: 0) == 360)
        #expect(TerminalInspectorWidthPolicy.idealWidth(forContentWidth: 0) == 480)
    }

    @Test func measuredCapNeverStarvesTheDetailColumn() {
        // Above the floor band the reserve must hold: window minus inspector
        // minus sidebar reserve keeps at least the detail reserve.
        for width: CGFloat in [880, 1000, 1200, 1470, 2000] {
            let maxW = TerminalInspectorWidthPolicy.maxWidth(forContentWidth: width)
            guard maxW > TerminalInspectorWidthPolicy.absoluteMin else { continue }
            let detailLeft = width - maxW - TerminalInspectorWidthPolicy.sidebarReserve
            #expect(
                detailLeft >= TerminalInspectorWidthPolicy.detailReserve - 0.001,
                "detail starved at width \(width): \(detailLeft)")
        }
    }

    @Test func quantizationSnapsDownToSixteenPointGrid() {
        #expect(TerminalInspectorWidthPolicy.quantizedContentWidth(1000) == 992)
        #expect(TerminalInspectorWidthPolicy.quantizedContentWidth(992) == 992)
        #expect(TerminalInspectorWidthPolicy.quantizedContentWidth(1007.9) == 992)
        #expect(TerminalInspectorWidthPolicy.quantizedContentWidth(0) == 0)
        #expect(TerminalInspectorWidthPolicy.quantizedContentWidth(-5) == 0)
        #expect(TerminalInspectorWidthPolicy.quantizedContentWidth(15) == 0)
    }

    @Test func quantizedZeroStillFallsBackToAbsoluteRange() {
        let quantized = TerminalInspectorWidthPolicy.quantizedContentWidth(12)
        #expect(TerminalInspectorWidthPolicy.maxWidth(forContentWidth: quantized) == 900)
    }
}
