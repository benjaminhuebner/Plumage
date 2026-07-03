import Foundation

// Resolves the repo's `NewProjectAssets/` tree via this file's own location, so
// ProjectCreation tests can drive composers and the scaffolder against the real
// assets without depending on the app bundle being built. `#filePath` here is
// `.../PlumageTests/TestHelpers/RepoAssets.swift`, three levels under the repo root.
enum RepoAssets {
    private static let thisFile = URL(filePath: #filePath)

    static var root: URL {
        thisFile
            .deletingLastPathComponent()  // TestHelpers/
            .deletingLastPathComponent()  // PlumageTests/
            .deletingLastPathComponent()  // repo root
            .appending(path: "NewProjectAssets", directoryHint: .isDirectory)
    }
}
