import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite struct NewProjectModelTests {
    // MARK: - Template step

    @Test func templateStepInvalidUntilKindPicked() {
        let model = NewProjectModel()
        #expect(model.isTypeStepValid == false)
        #expect(model.canAdvance == false)

        model.selectedTemplateID = ProjectKind.macOS.rawValue
        #expect(model.isTypeStepValid)
        #expect(model.canAdvance)
    }

    // MARK: - Options step (metadata)

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
        let model = NewProjectModel()
        model.name = name
        #expect(model.isMetadataStepValid == expected)
    }

    @Test func trimmingStripsWhitespace() {
        let model = NewProjectModel()
        model.name = "  MyApp  "
        model.tagline = "  A little app  "
        #expect(model.trimmedName == "MyApp")
        #expect(model.trimmedTagline == "A little app")
    }

    // MARK: - Navigation

    @Test func navigationWalksStepsForward() {
        let model = NewProjectModel()
        #expect(model.currentStep == .template)
        #expect(model.isFirstStep)
        #expect(model.isLastStep == false)

        model.selectedTemplateID = ProjectKind.iOS.rawValue
        model.advance()
        #expect(model.currentStep == .options)
        #expect(model.isLastStep)
        // Last step has no "Next".
        #expect(model.canAdvance == false)
    }

    @Test func navigationGoesBackAndClampsAtEdges() {
        let model = NewProjectModel()
        model.goBack()
        #expect(model.currentStep == .template)

        model.currentStep = .options
        model.goBack()
        #expect(model.currentStep == .template)
        // Clamps at the first step.
        model.goBack()
        #expect(model.currentStep == .template)
    }

    @Test func cannotAdvancePastInvalidStep() {
        let model = NewProjectModel()
        // Template step invalid → no advance.
        #expect(model.canAdvance == false)

        model.selectedTemplateID = ProjectKind.vapor.rawValue
        #expect(model.canAdvance)
    }

    // MARK: - Options step (git) / spec assembly

    @Test func gitSetupReflectsTogglesWhenEnabled() throws {
        let model = makeValidModel()
        model.createGitRepo = true
        model.plumageInGit = false
        model.claudeInGit = true
        model.createGitignore = false

        let spec = try #require(model.assembledSpec(projectDirectory: targetURL(name: "MyApp")))
        let git = try #require(spec.git)
        #expect(git.plumageInGit == false)
        #expect(git.claudeInGit == true)
        #expect(git.createGitignore == false)
    }

    @Test func noGitSetupWhenRepoDisabled() throws {
        let model = makeValidModel()
        model.createGitRepo = false
        // The per-flag toggles are irrelevant once the repo is off.
        model.plumageInGit = false

        let spec = try #require(model.assembledSpec(projectDirectory: targetURL(name: "MyApp")))
        #expect(spec.git == nil)
    }

    @Test func assembledSpecCarriesAllFields() throws {
        let model = NewProjectModel()
        model.selectedTemplateID = ProjectKind.hummingbird.rawValue
        model.name = "ignored-field"
        model.tagline = "  fast server  "

        let target = targetURL(name: "Birdy")
        let spec = try #require(model.assembledSpec(projectDirectory: target))
        #expect(spec.kind == .hummingbird)
        // The panel URL is authoritative: name follows the last path component,
        // not the options field.
        #expect(spec.name == "Birdy")
        #expect(spec.tagline == "fast server")
        #expect(spec.projectDirectory.lastPathComponent == "Birdy")
        #expect(spec.projectDirectory.standardizedFileURL == target.standardizedFileURL)
    }

    @Test func assembledSpecNilWithoutKind() throws {
        let model = NewProjectModel()
        model.name = "Thing"
        #expect(model.assembledSpec(projectDirectory: targetURL(name: "Thing")) == nil)

        model.selectedTemplateID = ProjectKind.other.rawValue
        #expect(model.assembledSpec(projectDirectory: targetURL(name: "Thing")) != nil)
    }

    // MARK: - Create gating

    @Test func cannotCreateUntilKindAndNameSet() {
        let model = NewProjectModel()
        #expect(model.canCreate == false)

        model.selectedTemplateID = ProjectKind.macOS.rawValue
        #expect(model.canCreate == false)  // still no name

        model.name = "MyApp"
        #expect(model.canCreate)
    }

    // MARK: - Error messages

    @Test func messagesCoverScaffoldErrors() {
        let dir = URL(filePath: "/tmp/Whatever")
        #expect(
            NewProjectModel.message(for: ProjectScaffoldError.directoryNotEmpty(dir))
                .isEmpty == false)
        #expect(
            NewProjectModel.message(for: ProjectScaffoldError.missingAssets(dir))
                .isEmpty == false)
        #expect(NewProjectModel.message(for: NewProjectError.incompleteForm).isEmpty == false)
    }

    @Test func createFailsFastWhenFormIncomplete() async {
        let model = NewProjectModel()
        // No kind → assembledSpec is nil → fails fast without touching disk.
        let result = await model.create(at: targetURL(name: "MyApp"))
        #expect(throwsIncompleteForm(result))
        #expect(model.errorMessage != nil)
        #expect(model.isCreating == false)
    }

    // MARK: - Helpers

    private func makeValidModel() -> NewProjectModel {
        let model = NewProjectModel()
        model.selectedTemplateID = ProjectKind.appleMultiplatform.rawValue
        model.name = "MyApp"
        return model
    }

    private func targetURL(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "plumage-newproj-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
    }

    private func throwsIncompleteForm(_ result: Result<CreatedProject, Error>) -> Bool {
        if case .failure(let error) = result, error as? NewProjectError == .incompleteForm {
            return true
        }
        return false
    }
}
