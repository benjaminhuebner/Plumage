import Foundation
import Testing

@testable import Plumage

@Suite("DiscoveredIssue sortedForKanban")
struct SortKeyTests {
    @Test("all nil orders sorts by id ascending")
    func allNilOrders() {
        let items: [DiscoveredIssue] = [
            valid(id: 10),
            valid(id: 2),
            valid(id: 5),
        ]
        #expect(ids(items.sortedForKanban()) == [2, 5, 10])
    }

    @Test("explicit orders override id-based fallback")
    func explicitOrdersOverride() {
        let items: [DiscoveredIssue] = [
            valid(id: 1, order: 100),
            valid(id: 2, order: 0.5),
            valid(id: 3),
        ]
        #expect(ids(items.sortedForKanban()) == [2, 3, 1])
    }

    @Test("mixed order and nil falls back to id for nils")
    func mixedOrderAndNil() {
        let items: [DiscoveredIssue] = [
            valid(id: 1, order: 50),
            valid(id: 7),
            valid(id: 2, order: 10),
        ]
        // id=7 (order nil → 7.0), id=2 (order 10), id=1 (order 50)
        #expect(ids(items.sortedForKanban()) == [7, 2, 1])
    }

    @Test("equal orders tie-break by id ascending")
    func equalOrdersTieBreakById() {
        let items: [DiscoveredIssue] = [
            valid(id: 7, order: 1.0),
            valid(id: 3, order: 1.0),
        ]
        #expect(ids(items.sortedForKanban()) == [3, 7])
    }

    @Test("equal id and order tie-break by folder name lowercased")
    func equalIdAndOrderTieBreakByFolderName() {
        let items: [DiscoveredIssue] = [
            valid(id: 7, folderName: "00007-bravo"),
            valid(id: 7, folderName: "00007-Alpha"),
            valid(id: 7, folderName: "00007-charlie"),
        ]
        let names = items.sortedForKanban().map(folderName(for:))
        #expect(names == ["00007-Alpha", "00007-bravo", "00007-charlie"])
    }

    @Test("invalid issues sort by extracted id with nil order")
    func invalidIssuesSort() {
        let items: [DiscoveredIssue] = [
            valid(id: 5),
            .invalid(
                folder: URL(filePath: "/tmp/x/.claude/issues/00002-broken"),
                error: .missingFrontmatter
            ),
        ]
        #expect(items.sortedForKanban().map(folderName(for:)) == ["00002-broken", "00005-x"])
    }

    private func valid(id: Int, folderName: String? = nil, order: Double? = nil) -> DiscoveredIssue {
        .valid(
            Issue(
                id: id,
                folderName: folderName ?? "\(String(format: "%05d", id))-x",
                title: "t",
                type: .feature,
                status: .approved,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/x",
                labels: [],
                model: nil,
                order: order
            )
        )
    }

    private func ids(_ items: [DiscoveredIssue]) -> [Int] {
        items.compactMap {
            if case .valid(let issue) = $0 { issue.id } else { nil }
        }
    }

    private func folderName(for item: DiscoveredIssue) -> String {
        switch item {
        case .valid(let issue): issue.folderName
        case .invalid(let folder, _): folder.lastPathComponent
        }
    }
}
