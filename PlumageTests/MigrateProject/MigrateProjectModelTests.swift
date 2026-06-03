import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite struct MigrateProjectModelTests {
    private func makeModel(
        folder: String = "MyFolder",
        detected: ProjectKind? = nil,
        isRepo: Bool = false,
        // Hermetic by default: resolve to the bundled default, not the user's manifest.
        store: TemplateCatalogStore = TemplateCatalogStore(manifestURL: nil)
    ) -> MigrateProjectModel {
        let url = URL(filePath: "/tmp/\(folder)", directoryHint: .isDirectory)
        return MigrateProjectModel(
            folderURL: url,
            detector: { _ in detected },
            repoStateReader: RepoStateReader(
                fileManager: { _ in isRepo },
                readFile: { _ in isRepo ? "ref: refs/heads/main\n" : nil }),
            store: store)
    }

    // A store backed by a temp manifest in which `disabled` templates are turned off.
    private func storeDisabling(_ disabled: [ProjectKind]) throws -> (TemplateCatalogStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "migrate-manifest-\(UUID().uuidString).json")
        let store = TemplateCatalogStore(manifestURL: url)
        var catalog = TemplateCatalog.bundledDefault
        for kind in disabled { catalog.setTemplateEnabled(id: kind.rawValue, false) }
        try store.save(catalog)
        return (store, url)
    }

    @Test func nameDefaultsToFolderName() {
        #expect(makeModel(folder: "Acme").name == "Acme")
    }

    @Test func templateStepInvalidUntilKindPicked() {
        let model = makeModel()
        #expect(model.isTypeStepValid == false)
        #expect(model.canAdvance == false)
        model.selectedTemplateID = ProjectKind.macOS.rawValue
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
        #expect(model.selectedTemplateID == ProjectKind.iOS.rawValue)
        #expect(model.isGitRepo)
    }

    @Test func loadMapsDetectedKindToItsPredefinedTemplateID() async {
        let model = makeModel(detected: .vapor)
        await model.load()
        #expect(model.selectedTemplateID == ProjectKind.vapor.rawValue)
    }

    @Test func loadWithNoDetectionLeavesSelectionEmpty() async {
        let model = makeModel(detected: nil)
        await model.load()
        #expect(model.detectedKind == nil)
        #expect(model.selectedTemplateID == nil)
        #expect(model.isTypeStepValid == false)
    }

    @Test func loadDoesNotPreselectADisabledDetectedTemplate() async throws {
        let (store, url) = try storeDisabling([.macOS])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = makeModel(detected: .macOS, store: store)
        await model.load()
        // Detection still records the kind, but a hidden template is never pre-selected.
        #expect(model.detectedKind == .macOS)
        #expect(model.selectedTemplateID == nil)
    }

    @Test func loadDoesNotOverrideUserChosenKind() async {
        let model = makeModel(detected: .iOS, isRepo: false)
        model.selectedTemplateID = ProjectKind.macOS.rawValue
        await model.load()
        #expect(model.detectedKind == .iOS)
        #expect(model.selectedTemplateID == ProjectKind.macOS.rawValue)
        #expect(model.isGitRepo == false)
    }

    @Test func assembledSpecMapsFields() {
        let model = makeModel(folder: "Acme")
        model.selectedTemplateID = ProjectKind.swiftCLI.rawValue
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
        model.selectedTemplateID = ProjectKind.macOS.rawValue
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
