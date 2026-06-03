import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// Drag payload for moving a template between categories in the sidebar. Carries
// just the template id; the drop target supplies the destination category. Scoped
// to the window — a same-process catalog edit, not an inter-app transfer.
nonisolated struct TemplateDragPayload: Codable, Sendable, Hashable {
    let templateID: String
}

nonisolated extension UTType {
    static let plumageTemplateDrag = UTType(exportedAs: "com.benjaminhuebner.plumage.template-drag")
}

nonisolated extension TemplateDragPayload: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plumageTemplateDrag)
    }
}
