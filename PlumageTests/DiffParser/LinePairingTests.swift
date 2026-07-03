import Testing

@testable import Plumage

@Suite("LinePairing")
struct LinePairingTests {
    private static func lines(_ kinds: [LineKind]) -> [Line] {
        kinds.enumerated().map { Line(kind: $0.element, content: "line \($0.offset)") }
    }

    static let pairingCases: [(kinds: [LineKind], expected: [LinePair])] = [
        ([], []),
        ([.context, .context], []),
        ([.removed, .added], [LinePair(removed: 0, added: 1)]),
        (
            [.removed, .removed, .added, .added],
            [LinePair(removed: 0, added: 2), LinePair(removed: 1, added: 3)]
        ),
        ([.removed, .removed, .removed, .added], [LinePair(removed: 0, added: 3)]),
        ([.removed, .added, .added, .added], [LinePair(removed: 0, added: 1)]),
        ([.added, .added], []),
        ([.removed, .removed], []),
        ([.added, .removed], []),
        ([.removed, .context, .added], []),
        (
            [.context, .removed, .added, .context, .removed, .removed, .added],
            [LinePair(removed: 1, added: 2), LinePair(removed: 4, added: 6)]
        ),
        (
            [.removed, .added, .removed, .added],
            [LinePair(removed: 0, added: 1), LinePair(removed: 2, added: 3)]
        ),
        ([.context, .added, .added, .removed, .context], []),
    ]

    @Test("pairs removal blocks with addition blocks index-wise", arguments: pairingCases)
    func pairing(testCase: (kinds: [LineKind], expected: [LinePair])) {
        #expect(LinePairing.pairs(in: Self.lines(testCase.kinds)) == testCase.expected)
    }

    @Test("pair indices point at the paired lines")
    func pairIndicesResolve() throws {
        let lines = Self.lines([.context, .removed, .removed, .added, .context])
        let pairs = LinePairing.pairs(in: lines)
        let pair = try #require(pairs.first)
        #expect(pairs.count == 1)
        #expect(lines[pair.removed].kind == .removed)
        #expect(lines[pair.added].kind == .added)
        #expect(lines[pair.removed].content == "line 1")
        #expect(lines[pair.added].content == "line 3")
    }
}
