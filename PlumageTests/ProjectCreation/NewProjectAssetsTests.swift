import Foundation
import Testing

@testable import Plumage

// PlumageTests is hosted by Plumage.app, so `Bundle.main` resolves to the app
// bundle and the folder-reference resources are reachable here.
@Suite("NewProjectAssets bundling")
struct NewProjectAssetsTests {
    @Test("Bundled asset tree is reachable via Bundle.main")
    func bundledRootExists() {
        let root = NewProjectAssets.bundledRoot
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("Known template is bundled and readable")
    func templateReadable() throws {
        let claude = NewProjectAssets.bundledRoot.appending(path: "templates/CLAUDE.md")
        let text = try String(contentsOf: claude, encoding: .utf8)
        #expect(text.contains("<<<PROJECT_NAME>>>"))
    }

    @Test("Auxiliary assets are bundled")
    func auxiliaryAssetsBundled() {
        let root = NewProjectAssets.bundledRoot
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: root.appending(path: "configs/swift-format").path))
        #expect(fm.fileExists(atPath: root.appending(path: "configs/swiftlint.yml").path))
        #expect(fm.fileExists(atPath: root.appending(path: "plumage/roadmap.py").path))
        #expect(fm.fileExists(atPath: root.appending(path: "issues/_TEMPLATE.md").path))
        #expect(fm.fileExists(atPath: root.appending(path: "templates/gitignore/macos.gitignore").path))
    }
}
