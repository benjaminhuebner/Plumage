import Foundation
import Testing

@testable import Plumage

@MainActor
struct RecentProjectsTests {
    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-\(UUID().uuidString).json")
    }

    @Test func capAtMaxItems() async throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }
        let sut = RecentProjects(storeURL: store)

        let overflow = RecentProjects.maxItems + 1
        for index in 0..<overflow {
            sut.add(
                url: URL(fileURLWithPath: "/tmp/project-\(index)"),
                name: "P\(index)"
            )
        }

        #expect(sut.items.count == RecentProjects.maxItems)
        #expect(sut.items.first?.name == "P\(overflow - 1)")
        #expect(sut.items.contains { $0.name == "P0" } == false)
    }

    @Test func duplicateAddMovesEntryToFront() async throws {
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

    @Test func updateChangesNameInPlaceWithoutReordering() async throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }
        let sut = RecentProjects(storeURL: store)

        let alpha = URL(fileURLWithPath: "/tmp/alpha")
        let beta = URL(fileURLWithPath: "/tmp/beta")
        sut.add(url: alpha, name: "Alpha")
        sut.add(url: beta, name: "Beta")  // beta is now at the front

        sut.update(url: alpha, name: "Renamed")

        // Renamed in place; order preserved (beta still first).
        #expect(sut.items.first?.url == beta.standardizedFileURL)
        #expect(sut.items.first(where: { $0.url == alpha.standardizedFileURL })?.name == "Renamed")

        // Persisted to disk.
        await sut.flushPendingWrites()
        let reloaded = RecentProjects(storeURL: store)
        await reloaded.load()
        #expect(reloaded.items.first(where: { $0.url == alpha.standardizedFileURL })?.name == "Renamed")
    }

    @Test func updateForUnknownURLIsNoOp() async throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }
        let sut = RecentProjects(storeURL: store)
        sut.add(url: URL(fileURLWithPath: "/tmp/alpha"), name: "Alpha")

        sut.update(url: URL(fileURLWithPath: "/tmp/ghost"), name: "Nope")

        #expect(sut.items.count == 1)
        #expect(sut.items.first?.name == "Alpha")
    }

    @Test func roundTripPersistence() async throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }

        let writer = RecentProjects(storeURL: store)
        writer.add(url: URL(fileURLWithPath: "/tmp/x"), name: "X")
        writer.add(url: URL(fileURLWithPath: "/tmp/y"), name: "Y")
        await writer.flushPendingWrites()

        let reader = RecentProjects(storeURL: store)
        await reader.load()
        #expect(reader.items.count == 2)
        #expect(reader.items[0].name == "Y")
        #expect(reader.items[1].name == "X")
    }

    @Test func emptyStoreYieldsEmptyItems() async throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }
        let sut = RecentProjects(storeURL: store)
        await sut.load()
        #expect(sut.items.isEmpty)
    }

    @Test func brokenStoreRecoversSilently() async throws {
        let store = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: store) }
        try Data("not valid json".utf8).write(to: store)

        let sut = RecentProjects(storeURL: store)
        await sut.load()
        #expect(sut.items.isEmpty)
    }
}
