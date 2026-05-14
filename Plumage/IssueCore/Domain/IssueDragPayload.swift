import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct IssueDragPayload: Codable, Sendable, Hashable {
    let folderName: String
    let currentStatus: IssueStatus
}

nonisolated extension IssueDragPayload: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plumageIssueDrag)
    }
}

nonisolated extension UTType {
    static let plumageIssueDrag = UTType(
        exportedAs: "com.benjaminhuebner.plumage.issue-drag"
    )
}
