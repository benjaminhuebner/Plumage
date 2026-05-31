import Foundation

// Wizard state for the New Project flow. UI-free so the validation and spec
// assembly are unit-testable without a view. The actual scaffolding lives in
// the `ProjectScaffolder` engine (#00054); this model only collects the inputs,
// validates them per step, and bridges the off-Main create call. The target
// directory itself comes from the macOS save panel at "Create" time, so the
// model carries no location state.
@MainActor
@Observable
final class NewProjectModel {
    enum Step: Int, CaseIterable {
        case template
        case options
    }

    var currentStep: Step = .template

    // Template step — nil until the user picks a kind, so "Next" stays disabled.
    var kind: ProjectKind?

    // Options step — metadata
    var name: String = ""
    var tagline: String = ""

    // Options step — git
    var createGitRepo: Bool = true
    var plumageInGit: Bool = true
    var claudeInGit: Bool = true
    var createGitignore: Bool = true

    // Create state — driven by `create(at:)`, read by the view for progress/banner.
    var isCreating: Bool = false
    var errorMessage: String?

    // MARK: - Derived input

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTagline: String {
        tagline.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // The options step bundles metadata + git; it gates on the metadata name.
    var isOptionsStepValid: Bool {
        isMetadataStepValid && isGitStepValid
    }

    func isValid(_ step: Step) -> Bool {
        switch step {
        case .template: isTypeStepValid
        case .options: isOptionsStepValid
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

    // Gates the "Create" button before the save panel even opens. The final
    // target directory (and thus the project name) comes from the panel.
    var canCreate: Bool {
        !isCreating
            && isTypeStepValid
            && isMetadataStepValid
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

    // Build the engine input from the save-panel result. The panel URL is
    // authoritative: the project folder and the recorded name follow
    // `projectDirectory.lastPathComponent`, not the options-field value (the
    // user may have edited the name inside the panel).
    func assembledSpec(projectDirectory: URL) -> NewProjectSpec? {
        guard let kind else { return nil }
        let name = projectDirectory.lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { return nil }

        let git =
            createGitRepo
            ? GitSetup(
                plumageInGit: plumageInGit,
                claudeInGit: claudeInGit,
                createGitignore: createGitignore)
            : nil

        return NewProjectSpec(
            kind: kind,
            name: name,
            tagline: trimmedTagline,
            projectDirectory: projectDirectory,
            git: git)
    }

    // MARK: - Create (State-as-Bridge)

    func create(at projectDirectory: URL) async -> Result<CreatedProject, Error> {
        guard let spec = assembledSpec(projectDirectory: projectDirectory) else {
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
