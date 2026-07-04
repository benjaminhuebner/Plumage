import CoreTransferable
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Plumage

@Suite("BranchDragPayload transfer")
struct BranchDragPayloadTests {
    @Test("codable round-trip preserves the branch name")
    func codableRoundTrip() throws {
        let payload = BranchDragPayload(branchName: "issue/00142-branch-drag-merge")
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(BranchDragPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test("transferable round-trip via NSItemProvider")
    func transferableRoundTrip() async throws {
        let payload = BranchDragPayload(branchName: "feature/drag-source")
        let provider = NSItemProvider()
        provider.register(payload)

        let loaded: BranchDragPayload = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: BranchDragPayload.self) { result in
                continuation.resume(with: result)
            }
        }
        #expect(loaded == payload)
    }

    @Test("UTType identifier matches the Info.plist declaration")
    func utTypeIdentifier() {
        #expect(UTType.plumageBranchDrag.identifier == "com.benjaminhuebner.plumage.branch-drag")
    }
}
