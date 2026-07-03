import Foundation
import UniformTypeIdentifiers

// Identity of the `.plumagetemplates` export file. The UTI is declared in
// Info.plist (conforms to public.zip-archive) so Finder routes double-clicks
// to Plumage; the extension check is what the drop/open paths branch on.
nonisolated enum TemplateArchiveFileType {
    static let fileExtension = "plumagetemplates"
    private static let identifier = "com.benjaminhuebner.plumage.template-archive"

    static var utType: UTType {
        UTType(identifier) ?? .zip
    }

    static func isArchive(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension
    }
}
