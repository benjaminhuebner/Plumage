import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite struct MigrateProjectModelTests {
    private func makeModel(
        folder: String = "MyFolder",
        detected: ProjectKind? = nil,
        isRepo: Bool = false
    ) -> MigrateProjectModel {
        let url = URL(filePath: "/tmp/\(folder)", directoryHint: .isDirectory)
        return MigrateProjectModel(
            folderURL: url,
            detector: { _ in detected },
            repoStateReader: RepoStateReader(
                fileManager: { _ in isRepo },
                readFile: { _ in isRepo ? "ref: refs/heads/main\n" : nil }))
    }

    @Test func nameDefaultsToFolderName() {
        #expect(makeModel(folder: "Acme").name == "Acme")
    }

    @Test func templateStepInvalidUntilKindPicked() {
        let model = makeModel()
        #expect(model.isTypeStepValid == false)
        #expect(model.canAdvance == false)
        model.kind = .macOS
        #expect(model.isTypeStepValid)
        #expect(model.canAdvance)
    }

    @Test(arguments: [
        ("", false),
        ("   ", false),
        ("/", false),
        ("a/b", false),
        (".", false),
        ("..", false),
        ("MyApp", true),
        ("  Spaced Name  ", true),
    ])
    func metadataValidation(name: String, expected: Bool) {
        let model = makeModel()
        model.name = name
        #expect(model.isMetadataStepValid == expected)
    }

    @Test func loadPreselectsDetectedKindAndRepoState() async {
        let model = makeModel(detected: .iOS, isRepo: true)
        await model.load()
        #expect(model.detectedKind == .iOS)
        #expect(model.kind == .iOS)
        #expect(model.isGitRepo)
    }

    @Test func loadDoesNotOverrideUserChosenKind() async {
        let model = makeModel(detected: .iOS, isRepo: false)
        model.kind = .macOS
        await model.load()
        #expect(model.detectedKind == .iOS)
        #expect(model.kind == .macOS)
        #expect(model.isGitRepo == false)
    }

    @Test func assembledSpecMapsFields() {
        let model = makeModel(folder: "Acme")
        model.kind = .swiftCLI
        model.tagline = "  A tool  "
        model.initGit = false
        model.plumageInGit = false
        model.claudeInGit = true
        model.createGitignore = false
        let spec = model.assembledSpec()
        #expect(spec?.kind == .swiftCLI)
        #expect(spec?.name == "Acme")
        #expect(spec?.tagline == "A tool")
        #expect(spec?.git.initIfMissing == false)
        #expect(spec?.git.plumageInGit == false)
        #expect(spec?.git.claudeInGit == true)
        #expect(spec?.git.createGitignore == false)
    }

    @Test func assembledSpecNilWithoutKind() {
        let model = makeModel()
        model.name = "Acme"
        #expect(model.assembledSpec() == nil)
    }

    @Test func canMigrateRequiresKindAndName() {
        let model = makeModel()
        model.name = ""
        #expect(model.canMigrate == false)
        model.kind = .macOS
        #expect(model.canMigrate == false)
        model.name = "Acme"
        #expect(model.canMigrate)
    }

    @Test func messageForAlreadyPlumageIsActionable() {
        let message = MigrateProjectModel.message(
            for: ProjectMigrateError.alreadyPlumage(URL(filePath: "/tmp/x.plumage")))
        #expect(message.contains("already a Plumage project"))
    }
}
