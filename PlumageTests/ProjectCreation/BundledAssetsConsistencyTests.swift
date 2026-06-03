import Foundation
import Testing

@testable import Plumage

// Ties the ProjectKindProfile table to the bundled assets: anything a profile
// names (hooks, template layers, gitignore tags) must actually exist in the
// bundle, and the generalized skill/hook bodies must carry their tokens.
@Suite("Bundled assets consistency")
struct BundledAssetsConsistencyTests {
    private let root = NewProjectAssets.bundledRoot
    private let fm = FileManager.default

    private func exists(_ rel: String) -> Bool {
        fm.fileExists(atPath: root.appending(path: rel).path)
    }

    @Test("Every hook referenced by a profile is bundled")
    func hooksExist() {
        for kind in ProjectKind.allCases {
            for hook in kind.profile.hookNames {
                #expect(exists("hooks/\(hook).sh"), "missing hook \(hook).sh for \(kind)")
            }
        }
    }

    @Test("Every template layer referenced by a profile is bundled")
    func templateLayersExist() {
        for kind in ProjectKind.allCases {
            for layer in kind.profile.templateLayers {
                #expect(
                    exists("templates/\(layer)/CLAUDE.md"),
                    "missing template \(layer)/CLAUDE.md for \(kind)")
            }
        }
        #expect(exists("templates/CLAUDE.md"))
    }

    @Test("Every gitignore tag (plus the always-on macOS block) is bundled")
    func gitignoreFragmentsExist() {
        for kind in ProjectKind.allCases {
            for tag in kind.profile.gitignoreTags + ["macos"] {
                #expect(exists("templates/gitignore/\(tag).gitignore"), "missing gitignore \(tag) for \(kind)")
            }
        }
    }
}
