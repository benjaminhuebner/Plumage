import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite struct NewProjectModelTests {
    // MARK: - Type step

    @Test func typeStepInvalidUntilKindPicked() {
        let model = NewProjectModel()
        #expect(model.isTypeStepValid == false)
        #expect(model.canAdvance == false)

        model.kind = .macOS
        #expect(model.isTypeStepValid)
        #expect(model.canAdvance)
    }

    // MARK: - Metadata step

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
        #expect(model.currentStep == .type)
        #expect(model.isFirstStep)
        #expect(model.isLastStep == false)

        model.kind = .iOS
        model.advance()
        #expect(model.currentStep == .metadata)

        model.name = "MyApp"
        model.advance()
        #expect(model.currentStep == .git)

        model.advance()
        #expect(model.currentStep == .location)
        #expect(model.isLastStep)
        // Last step has no "Next".
        #expect(model.canAdvance == false)
    }

    @Test func navigationGoesBackAndClampsAtEdges() {
        let model = NewProjectModel()
        model.goBack()
        #expect(model.currentStep == .type)

        model.currentStep = .location
        model.goBack()
        #expect(model.currentStep == .git)
        model.goBack()
        #expect(model.currentStep == .metadata)
    }

    @Test func cannotAdvancePastInvalidStep() {
        let model = NewProjectModel()
        // Type step invalid → no advance.
        #expect(model.canAdvance == false)

        model.kind = .vapor
        model.currentStep = .metadata
        // Metadata invalid (empty name) → no advance.
        #expect(model.canAdvance == false)

        model.name = "Server"
        #expect(model.canAdvance)
    }

    // MARK: - Git step / spec assembly

    @Test func gitSetupReflectsTogglesWhenEnabled() throws {
        let model = makeValidModel()
        model.createGitRepo = true
        model.plumageInGit = false
        model.claudeInGit = true
        model.createGitignore = false

        let spec = try #require(model.assembledSpec)
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

        let spec = try #require(model.assembledSpec)
        #expect(spec.git == nil)
    }

    @Test func assembledSpecCarriesAllFields() throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let model = NewProjectModel()
        model.kind = .hummingbird
        model.name = "  Birdy  "
        model.tagline = "  fast server  "
        model.parentDirectory = parent

        let spec = try #require(model.assembledSpec)
        #expect(spec.kind == .hummingbird)
        #expect(spec.name == "Birdy")
        #expect(spec.tagline == "fast server")
        #expect(spec.projectDirectory.lastPathComponent == "Birdy")
        #expect(
            spec.projectDirectory.deletingLastPathComponent().standardizedFileURL
                == parent.standardizedFileURL)
    }

    @Test func assembledSpecNilWhenIncomplete() throws {
        let model = NewProjectModel()
        #expect(model.assembledSpec == nil)  // no kind, no name, no parent

        model.kind = .other
        #expect(model.assembledSpec == nil)  // still no name / parent

        model.name = "Thing"
        #expect(model.assembledSpec == nil)  // still no parent

        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        model.parentDirectory = parent
        #expect(model.assembledSpec != nil)
    }

    // MARK: - Location step

    @Test func locationInvalidWithoutParent() {
        let model = NewProjectModel()
        model.kind = .macOS
        model.name = "MyApp"
        #expect(model.projectDirectory == nil)
        #expect(model.isLocationStepValid == false)
    }

    @Test func locationValidForFreshTarget() throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let model = NewProjectModel()
        model.kind = .macOS
        model.name = "MyApp"
        model.parentDirectory = parent
        model.refreshTargetExists()

        #expect(model.projectDirectory?.lastPathComponent == "MyApp")
        #expect(model.targetExists == false)
        #expect(model.isLocationStepValid)
        #expect(model.canCreate)
    }

    @Test func locationInvalidOnCollision() throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let existing = parent.appending(path: "MyApp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        let model = NewProjectModel()
        model.kind = .macOS
        model.name = "MyApp"
        model.parentDirectory = parent
        model.refreshTargetExists()

        #expect(model.targetExists)
        #expect(model.isLocationStepValid == false)
        #expect(model.canCreate == false)
    }

    @Test func refreshClearsStaleCollisionWhenTargetMissing() throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let existing = parent.appending(path: "MyApp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        let model = NewProjectModel()
        model.kind = .macOS
        model.name = "MyApp"
        model.parentDirectory = parent
        model.refreshTargetExists()
        #expect(model.targetExists)

        // The target disappears → a refresh must clear the stale collision flag.
        try FileManager.default.removeItem(at: existing)
        model.refreshTargetExists()
        #expect(model.targetExists == false)
        #expect(model.isLocationStepValid)
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
        let result = await model.create()
        #expect(throwsIncompleteForm(result))
        #expect(model.errorMessage != nil)
        #expect(model.isCreating == false)
    }

    // MARK: - Helpers

    private func makeValidModel() -> NewProjectModel {
        let model = NewProjectModel()
        model.kind = .appleMultiplatform
        model.name = "MyApp"
        model.parentDirectory = FileManager.default.temporaryDirectory
            .appending(path: "plumage-newproj-\(UUID().uuidString)", directoryHint: .isDirectory)
        return model
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "plumage-newproj-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func throwsIncompleteForm(_ result: Result<CreatedProject, Error>) -> Bool {
        if case .failure(let error) = result, error as? NewProjectError == .incompleteForm {
            return true
        }
        return false
    }
}
