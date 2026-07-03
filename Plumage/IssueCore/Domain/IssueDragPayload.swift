import CoreTransferable
import UniformTypeIdentifiers

nonisolated struct IssueDragPayload: Codable, Sendable, Hashable {
    let folderName: String
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
