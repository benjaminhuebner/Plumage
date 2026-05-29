import Foundation

// The bundled source-of-truth tree for new projects. Attached to the app target
// as a folder reference, so it lands verbatim in
// `<App>.app/Contents/Resources/NewProjectAssets/`. Composers and the scaffolder
// read templates, gitignore fragments, skills, hooks, configs and docs from here.
// Deliberately a sibling of `Plumage/` in the repo (not under it) so the
// file-system-synchronized group doesn't flatten same-named files onto Resources.
nonisolated enum NewProjectAssets {
    static let folderName = "NewProjectAssets"

    static var bundledRoot: URL {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
            .appending(component: folderName, directoryHint: .isDirectory)
    }
}
