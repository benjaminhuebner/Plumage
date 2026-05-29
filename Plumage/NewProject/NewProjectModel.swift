import Foundation

// Wizard state for the New Project flow. UI-free so the validation and spec
// assembly are unit-testable without a view. The actual scaffolding lives in
// the `ProjectScaffolder` engine (#00054); this model only collects a
// `NewProjectSpec`, validates it per step, and bridges the off-Main create call.
@MainActor
@Observable
final class NewProjectModel {
    enum Step: Int, CaseIterable {
        case type
        case metadata
        case git
        case location
    }

    var currentStep: Step = .type

    // Step 1 — nil until the user picks a kind, so "Next" stays disabled.
    var kind: ProjectKind?

    // Step 2
    var name: String = ""
    var tagline: String = ""

    // Step 3
    var createGitRepo: Bool = true
    var plumageInGit: Bool = true
    var claudeInGit: Bool = true
    var createGitignore: Bool = true

    // Step 4
    var parentDirectory: URL?

    // Create state — driven by `create()`, read by the view for progress/banner.
    var isCreating: Bool = false
    var errorMessage: String?

    // MARK: - Derived input

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTagline: String {
        tagline.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Project folder is `<parent>/<name>` — the user names the project in step 2,
    // so step 4 only picks the parent directory.
    var projectDirectory: URL? {
        guard let parentDirectory, isMetadataStepValid else { return nil }
        return parentDirectory.appending(path: trimmedName, directoryHint: .isDirectory)
    }

    var projectDirectoryExists: Bool {
        guard let projectDirectory else { return false }
        return FileManager.default.fileExists(atPath: projectDirectory.path)
    }

    // MARK: - Per-step validation (pure)

    var isTypeStepValid: Bool {
        kind != nil
    }

    var isMetadataStepValid: Bool {
        let value = trimmedName
        return !value.isEmpty && !value.contains("/") && value != "." && value != ".."
    }

    // Git step is always valid: the toggles always describe a usable GitSetup.
    var isGitStepValid: Bool {
        true
    }

    var isLocationStepValid: Bool {
        projectDirectory != nil && !projectDirectoryExists
    }

    func isValid(_ step: Step) -> Bool {
        switch step {
        case .type: isTypeStepValid
        case .metadata: isMetadataStepValid
        case .git: isGitStepValid
        case .location: isLocationStepValid
        }
    }

    // MARK: - Navigation

    var isFirstStep: Bool {
        currentStep == Step.allCases.first
    }

    var isLastStep: Bool {
        currentStep == Step.allCases.last
    }

    // "Next" is offered on every step but the last; enabled once the current
    // step validates.
    var canAdvance: Bool {
        !isLastStep && isValid(currentStep)
    }

    var canCreate: Bool {
        !isCreating
            && isTypeStepValid
            && isMetadataStepValid
            && isLocationStepValid
    }

    func advance() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func goBack() {
        guard let previous = Step(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
    }

    // MARK: - Spec assembly

    var assembledSpec: NewProjectSpec? {
        guard
            let kind,
            let projectDirectory,
            isMetadataStepValid
        else { return nil }

        let git =
            createGitRepo
            ? GitSetup(
                plumageInGit: plumageInGit,
                claudeInGit: claudeInGit,
                createGitignore: createGitignore)
            : nil

        return NewProjectSpec(
            kind: kind,
            name: trimmedName,
            tagline: trimmedTagline,
            projectDirectory: projectDirectory,
            git: git)
    }

    // MARK: - Create (State-as-Bridge)

    func create() async -> Result<CreatedProject, Error> {
        guard let spec = assembledSpec else {
            let error = NewProjectError.incompleteForm
            errorMessage = Self.message(for: error)
            return .failure(error)
        }

        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            // Off-Main: the scaffolder does synchronous disk I/O and a git
            // subprocess. Pattern mirrors NavigatorModel's detached file work.
            let created = try await Task.detached(priority: .userInitiated) {
                try await ProjectScaffolder().create(spec: spec)
            }.value
            return .success(created)
        } catch {
            errorMessage = Self.message(for: error)
            return .failure(error)
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? NewProjectError {
            switch error {
            case .incompleteForm:
                return "Some required information is missing."
            }
        }
        if let error = error as? ProjectScaffoldError {
            switch error {
            case .directoryNotEmpty:
                return "A folder with that name already exists and isn't empty. "
                    + "Pick another name or location."
            case .missingAssets:
                return "Project templates are missing from the app bundle. "
                    + "Try reinstalling Plumage."
            }
        }
        return error.localizedDescription
    }
}

nonisolated enum NewProjectError: Error, Equatable {
    case incompleteForm
}
