import Foundation
import Testing

@testable import Plumage

@Suite("CardLabelFit")
struct CardLabelFitTests {
    @Test("an unmeasured (zero) width shows all; onGeometryChange corrects it")
    func zeroWidthShowsAll() {
        #expect(CardLabelFit.fitCount(labels: ["a", "b", "c"], width: 0) == 3)
    }

    @Test("a wide row fits every label")
    func wideFitsAll() {
        #expect(CardLabelFit.fitCount(labels: ["ui", "perf"], width: 1000) == 2)
    }

    @Test("empty labels fit zero")
    func emptyFitsZero() {
        #expect(CardLabelFit.fitCount(labels: [], width: 200) == 0)
    }

    @Test("a narrow row truncates and leaves room for the overflow pill")
    func narrowTruncates() {
        let labels = ["alpha", "beta", "gamma", "delta"]
        let count = CardLabelFit.fitCount(labels: labels, width: 120)
        #expect(count < labels.count)
    }
}
