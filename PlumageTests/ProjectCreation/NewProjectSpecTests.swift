import Foundation
import Testing

@testable import Plumage

@Suite("NewProjectSpec")
struct NewProjectSpecTests {
    @Test("GitSetup defaults to including everything")
    func gitSetupDefaults() {
        let setup = GitSetup()
        #expect(setup.plumageInGit)
        #expect(setup.claudeInGit)
        #expect(setup.createGitignore)
    }

    @Test("NewProjectSpec defaults git to nil (no repo)")
    func specGitDefaultsNil() {
        let spec = NewProjectSpec(
            kind: .macOS,
            name: "Acme",
            tagline: "A thing",
            projectDirectory: URL(filePath: "/tmp/acme")
        )
        #expect(spec.git == nil)
        #expect(spec.kind == .macOS)
        #expect(spec.name == "Acme")
    }
}
