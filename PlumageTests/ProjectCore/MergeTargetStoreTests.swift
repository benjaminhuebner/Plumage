import Foundation
import Testing

@testable import Plumage

@Suite("MergeTargetStore")
struct MergeTargetStoreTests {
    private final class Fixture {
        let bundle: URL

        init() throws {
            bundle = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "PlumageMergeTargetStore-\(UUID().uuidString)/Test.plumage", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
    }

    @Test("load returns nil when merge-target.json is absent")
    func loadMissingReturnsNil() throws {
        let fixture = try Fixture()
        #expect(MergeTargetStore.load(bundle: fixture.bundle) == nil)
    }

    @Test("save/load round-trips the target branch")
    func saveRoundTrips() throws {
        let fixture = try Fixture()
        try MergeTargetStore.save("release/1.0", bundle: fixture.bundle)
        #expect(MergeTargetStore.load(bundle: fixture.bundle) == "release/1.0")
    }

    @Test("save overwrites a previous choice")
    func saveOverwrites() throws {
        let fixture = try Fixture()
        try MergeTargetStore.save("main", bundle: fixture.bundle)
        try MergeTargetStore.save("develop", bundle: fixture.bundle)
        #expect(MergeTargetStore.load(bundle: fixture.bundle) == "develop")
    }

    @Test("corrupt merge-target.json loads as nil")
    func corruptLoadsAsNil() throws {
        let fixture = try Fixture()
        let url = fixture.bundle.appendingPathComponent(MergeTargetStore.fileName)
        try "{ this is not json".write(to: url, atomically: true, encoding: .utf8)
        #expect(MergeTargetStore.load(bundle: fixture.bundle) == nil)
    }
}
