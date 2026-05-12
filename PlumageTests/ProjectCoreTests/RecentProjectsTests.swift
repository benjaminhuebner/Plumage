import Foundation
import Testing

@testable import Plumage

@MainActor
struct RecentProjectsTests {
    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-\(UUID().uuidString).json")
    }

    @Test func capAtFifty() throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }
        let sut = RecentProjects(storeURL: store)

        for index in 0..<51 {
            sut.add(
                url: URL(fileURLWithPath: "/tmp/project-\(index)"),
                name: "P\(index)"
            )
        }

        #expect(sut.items.count == RecentProjects.maxItems)
        #expect(sut.items.first?.name == "P50")
        #expect(sut.items.contains { $0.name == "P0" } == false)
    }

    @Test func duplicateAddMovesEntryToFront() throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }
        let sut = RecentProjects(storeURL: store)

        let alpha = URL(fileURLWithPath: "/tmp/alpha")
        let beta = URL(fileURLWithPath: "/tmp/beta")
        sut.add(url: alpha, name: "Alpha")
        sut.add(url: beta, name: "Beta")
        sut.add(url: alpha, name: "Alpha")

        #expect(sut.items.count == 2)
        #expect(sut.items[0].url == alpha)
        #expect(sut.items[1].url == beta)
    }

    @Test func roundTripPersistence() throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }

        let writer = RecentProjects(storeURL: store)
        writer.add(url: URL(fileURLWithPath: "/tmp/x"), name: "X")
        writer.add(url: URL(fileURLWithPath: "/tmp/y"), name: "Y")

        let reader = RecentProjects(storeURL: store)
        #expect(reader.items.count == 2)
        #expect(reader.items[0].name == "Y")
        #expect(reader.items[1].name == "X")
    }

    @Test func emptyStoreYieldsEmptyItems() throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }
        let sut = RecentProjects(storeURL: store)
        #expect(sut.items.isEmpty)
    }

    @Test func brokenStoreRecoversSilently() throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }
        try Data("not valid json".utf8).write(to: store)

        let sut = RecentProjects(storeURL: store)
        #expect(sut.items.isEmpty)
    }
}
