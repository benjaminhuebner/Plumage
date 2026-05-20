import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct IssueDragPayload: Codable, Sendable, Hashable {
    let folderName: String
    // Re-added (supersedes 2026-05-14 Code-Review removal) so the sidebar drop
    // handler can distinguish status-change vs same-column reorder before
    // calling FrontmatterMutator. The kanban-board path doesn't need it, but
    // the carry cost on the payload is negligible.
    let currentStatus: IssueStatus
}

nonisolated extension UTType {
    static let plumageIssueDrag = UTType(exportedAs: "com.benjaminhuebner.plumage.issue-drag")
}

nonisolated extension IssueDragPayload: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plumageIssueDrag)
        ProxyRepresentation(exporting: \.folderName)
    }
}
