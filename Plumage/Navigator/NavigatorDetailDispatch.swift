import Foundation

// Pure suffix/basename-driven mapping from a project-relative path to the
// detail view that should render it. Separated from `NavigatorDetail` so it
// can be unit-tested without SwiftUI.
nonisolated enum FileDetailViewKind: Equatable, Sendable {
    case doc
    case info
    case image
}

nonisolated enum NavigatorDetailDispatch {
    // File extensions that get a NSImageView inline preview. macOS recognises
    // many more via NSImage(contentsOf:); the curated set here is the one
    // typical .claude/ / .plumage/ workflows produce or import.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp",
    ]

    // Extensions that should render as `FileInfoView` with the
    // "Open in Xcode" button surfaced. Anything outside this set still gets
    // FileInfoView, just without the Xcode button.
    static let codeExtensions: Set<String> = [
        "swift", "xcodeproj", "xcworkspace",
    ]

    // Basenames that route to DocEditorView even when their extension is not
    // `.md` — the in-app JSON settings editors we keep.
    static let editableBasenames: Set<String> = [
        "settings.json", "settings.local.json",
    ]

    static func detailViewKind(for relativePath: String) -> FileDetailViewKind {
        let lower = relativePath.lowercased()
        let nameNS = lower as NSString
        let ext = nameNS.pathExtension
        let basename = nameNS.lastPathComponent
        if ext == "md" {
            return .doc
        }
        if editableBasenames.contains(basename) {
            return .doc
        }
        if imageExtensions.contains(ext) {
            return .image
        }
        return .info
    }
}
