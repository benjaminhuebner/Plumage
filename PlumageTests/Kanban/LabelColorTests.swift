import Testing

@testable import Plumage

@Suite("LabelColor")
struct LabelColorTests {
    @Test("stableHash is deterministic for the same input")
    func determinism() {
        let label = "issue/00005-kanban"
        #expect(LabelColor.stableHash(label) == LabelColor.stableHash(label))
    }

    @Test("four pinned labels resolve to expected slot indices")
    func pinnedIndices() {
        let modulo = UInt32(LabelColor.paletteNames.count)
        #expect(LabelColor.stableHash("feature") % modulo == 5)
        #expect(LabelColor.stableHash("chore") % modulo == 2)
        #expect(LabelColor.stableHash("v0.1") % modulo == 2)
        #expect(LabelColor.stableHash("bootstrap") % modulo == 1)
    }

    @Test("stableHash modulo palette count stays inside the palette range")
    func rangeConstraint() {
        let modulo = UInt32(LabelColor.paletteNames.count)
        let samples = [
            "", "a", "feature", "chore", "v0.1", "bootstrap",
            "the quick brown fox jumps over the lazy dog",
            "🦜", "label-with-dashes", "00005-kanban",
        ]
        for sample in samples {
            let index = LabelColor.stableHash(sample) % modulo
            #expect(index < modulo)
        }
    }

    @Test("paletteNames lists eight slots in Label1...Label8 order")
    func paletteShape() {
        #expect(LabelColor.paletteNames == (1...8).map { "Label\($0)" })
    }
}
