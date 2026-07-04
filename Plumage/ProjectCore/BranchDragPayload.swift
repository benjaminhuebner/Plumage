import CoreTransferable
import UniformTypeIdentifiers

nonisolated struct BranchDragPayload: Codable, Sendable, Hashable {
    let branchName: String
}

nonisolated extension UTType {
    static let plumageBranchDrag = UTType(
        exportedAs: "com.benjaminhuebner.plumage.branch-drag")
}

nonisolated extension BranchDragPayload: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plumageBranchDrag)
        ProxyRepresentation(exporting: \.branchName)
    }
}
