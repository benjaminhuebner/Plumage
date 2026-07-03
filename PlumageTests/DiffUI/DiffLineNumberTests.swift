import Testing

@testable import Plumage

@Suite("DiffLineNumber")
struct DiffLineNumberTests {
    @Test("numbers walk old and new counters per line kind")
    func numbering() {
        let hunk = Hunk(
            oldStart: 10, oldCount: 3, newStart: 20, newCount: 4,
            lines: [
                Line(kind: .context, content: "a"),
                Line(kind: .removed, content: "b"),
                Line(kind: .added, content: "c"),
                Line(kind: .added, content: "d"),
                Line(kind: .context, content: "e"),
            ]
        )
        let numbers = DiffLineNumber.numbers(for: hunk)
        #expect(
            numbers == [
                DiffLineNumber(old: 10, new: 20),
                DiffLineNumber(old: 11, new: nil),
                DiffLineNumber(old: nil, new: 21),
                DiffLineNumber(old: nil, new: 22),
                DiffLineNumber(old: 12, new: 23),
            ])
    }

    @Test("column digits cover the highest line number in the hunk")
    func columnDigits() {
        let small = Hunk(oldStart: 1, oldCount: 3, newStart: 1, newCount: 3)
        #expect(DiffLineNumber.columnDigits(for: small) == 1)
        let large = Hunk(oldStart: 990, oldCount: 20, newStart: 5, newCount: 4)
        #expect(DiffLineNumber.columnDigits(for: large) == 4)
    }
}
