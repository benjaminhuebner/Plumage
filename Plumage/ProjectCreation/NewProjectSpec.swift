import Foundation

// The full input contract for `ProjectScaffolder.create(spec:)`. SwiftUI-free so
// the wizard (Issue B) can assemble it without coupling the engine to any view.
nonisolated struct NewProjectSpec: Hashable, Sendable {
    let kind: ProjectKind
    // The catalog template to scaffold. For a predefined template this equals
    // `kind.rawValue`; a custom template carries its own id (and `kind` is `.other`).
    // The engine resolves effective content by this id; `kind` only gates the
    // ProjectKind-specific bits (Swift config files).
    let templateID: String
    let name: String
    let tagline: String
    let projectDirectory: URL
    let git: GitSetup?

    init(
        kind: ProjectKind, templateID: String? = nil, name: String, tagline: String,
        projectDirectory: URL, git: GitSetup? = nil
    ) {
        self.kind = kind
        self.templateID = templateID ?? kind.rawValue
        self.name = name
        self.tagline = tagline
        self.projectDirectory = projectDirectory
        self.git = git
    }
}

// `nil` `GitSetup` on a `NewProjectSpec` means "no repo". A present value always
// initialises a repo; the three flags control what gets excluded from it.
nonisolated struct GitSetup: Hashable, Sendable {
    let plumageInGit: Bool
    let claudeInGit: Bool
    let createGitignore: Bool

    init(plumageInGit: Bool = true, claudeInGit: Bool = true, createGitignore: Bool = true) {
        self.plumageInGit = plumageInGit
        self.claudeInGit = claudeInGit
        self.createGitignore = createGitignore
    }
}
