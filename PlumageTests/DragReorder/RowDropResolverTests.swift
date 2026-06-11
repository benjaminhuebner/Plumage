import CoreGraphics
import Testing

@testable import Plumage

@Suite("resolveRowDrop")
struct RowDropResolverTests {
    private let spacing: CGFloat = 4
    private let placeholderHeight: CGFloat = 24
    private let container = CGRect(x: 0, y: 0, width: 200, height: 600)

    // Variable heights: a short row (24), a tall header-like row (40), a short row.
    private var frames: [String: CGRect] {
        [
            "a": CGRect(x: 0, y: 0, width: 200, height: 24),
            "b": CGRect(x: 0, y: 28, width: 200, height: 40),
            "c": CGRect(x: 0, y: 72, width: 200, height: 24),
        ]
    }

    @Test("cursor above a row's mid returns before that row")
    func beforeRow() {
        let resolution = resolveRowDrop(
            cursorY: 40,
            orderedRowIDs: ["a", "b", "c"],
            rowFrames: frames,
            placeholderHeight: placeholderHeight,
            spacing: spacing,
            containerFrame: container
        )
        #expect(resolution.position == .before("b"))
    }

    @Test("insertion frame for before sits one placeholder-height plus spacing above the row")
    func beforeInsertionFrame() throws {
        let resolution = resolveRowDrop(
            cursorY: 40,
            orderedRowIDs: ["a", "b", "c"],
            rowFrames: frames,
            placeholderHeight: placeholderHeight,
            spacing: spacing,
            containerFrame: container
        )
        let target = try #require(frames["b"])
        #expect(resolution.insertionFrame.minY == target.minY - spacing - placeholderHeight)
        #expect(resolution.insertionFrame.height == placeholderHeight)
    }

    @Test("variable row heights classify by each row's own midY")
    func variableHeightsUseOwnMid() {
        // y=50 is past b.midY (48) despite being well inside b's 40pt rect,
        // so the slot falls to before(c), not before(b).
        let resolution = resolveRowDrop(
            cursorY: 50,
            orderedRowIDs: ["a", "b", "c"],
            rowFrames: frames,
            placeholderHeight: placeholderHeight,
            spacing: spacing,
            containerFrame: container
        )
        #expect(resolution.position == .before("c"))
    }

    @Test("cursor past the last row's mid returns after last")
    func afterLast() throws {
        let resolution = resolveRowDrop(
            cursorY: 500,
            orderedRowIDs: ["a", "b", "c"],
            rowFrames: frames,
            placeholderHeight: placeholderHeight,
            spacing: spacing,
            containerFrame: container
        )
        let last = try #require(frames["c"])
        #expect(resolution.position == .after("c"))
        #expect(resolution.insertionFrame.minY == last.maxY + spacing)
    }

    @Test("empty row list returns empty with the container frame")
    func emptyRows() {
        let resolution = resolveRowDrop(
            cursorY: 100,
            orderedRowIDs: [],
            rowFrames: [:],
            placeholderHeight: placeholderHeight,
            spacing: spacing,
            containerFrame: container
        )
        #expect(resolution.position == .empty)
        #expect(resolution.insertionFrame == container)
    }

    @Test("rows without measured frames are skipped")
    func missingFramesSkipped() {
        var partial = frames
        partial.removeValue(forKey: "b")
        let resolution = resolveRowDrop(
            cursorY: 40,
            orderedRowIDs: ["a", "b", "c"],
            rowFrames: partial,
            placeholderHeight: placeholderHeight,
            spacing: spacing,
            containerFrame: container
        )
        #expect(resolution.position == .before("c"))
    }

    @Test("no measured frames at all falls through to after last")
    func noFramesFallsThrough() {
        let resolution = resolveRowDrop(
            cursorY: 40,
            orderedRowIDs: ["a", "b"],
            rowFrames: [:],
            placeholderHeight: placeholderHeight,
            spacing: spacing,
            containerFrame: container
        )
        #expect(resolution.position == .after("b"))
    }
}
