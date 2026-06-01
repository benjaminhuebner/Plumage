import Foundation

@MainActor
@Observable
final class MigrateProjectModel {
    enum Step: Int, CaseIterable {
        case template
        case options
    }

    let folderURL: URL

    var currentStep: Step = .template

    var detectedKind: ProjectKind?
    var kind: ProjectKind?

    var name: String
    var tagline: String = ""

    var isGitRepo: Bool = false
    var initGit: Bool = true
    var plumageInGit: Bool = true
    var claudeInGit: Bool = true
    var createGitignore: Bool = true

    var isMigrating: Bool = false
    var error: String?
    var report: MigrationReport?
    private(set) var migratedProject: CreatedProject?

    private var didLoad = false
    private let detector: @Sendable (URL) -> ProjectKind?
    private let repoStateReader: RepoStateReader

    init(
        folderURL: URL,
        detector: @escaping @Sendable (URL) -> ProjectKind? = { ProjectKindDetector.detect(in: $0) },
        repoStateReader: RepoStateReader = RepoStateReader()
    ) {
        self.folderURL = folderURL
        self.name = folderURL.lastPathComponent
        self.detector = detector
        self.repoStateReader = repoStateReader
    }

    // MARK: - Setup detection

    // Off-Main folder inspection: detect the project kind and whether the folder
    // is already a git repo. Idempotent — safe to call from `.task` on every
    // appearance. A user-chosen `kind` is never overwritten by detection.
    func load() async {
        guard !didLoad else { return }

        let url = folderURL
        let detect = detector
        let reader = repoStateReader
        let result = await Task.detached(priority: .userInitiated) { () -> (ProjectKind?, Bool) in
            (detect(url), reader.read(repoURL: url).isGitRepo)
        }.value

        // A cancelled `.task(id:)` (folder changed mid-detection) must neither
        // write stale results nor poison `didLoad` against the new folder.
        guard !Task.isCancelled else { return }
        didLoad = true
        detectedKind = result.0
        if kind == nil { kind = result.0 }
        isGitRepo = result.1
    }

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

    static func isValidName(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && value != "." && value != ".."
    }

    var isMetadataStepValid: Bool {
        Self.isValidName(trimmedName)
    }

    var isOptionsStepValid: Bool {
        isMetadataStepValid
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

    var canAdvance: Bool {
        !isLastStep && isValid(currentStep)
    }

    var canMigrate: Bool {
        !isMigrating && isTypeStepValid && isMetadataStepValid
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

    func assembledSpec() -> MigrationSpec? {
        guard let kind else { return nil }
        let name = trimmedName
        guard Self.isValidName(name) else { return nil }

        return MigrationSpec(
            projectDirectory: folderURL,
            kind: kind,
            name: name,
            tagline: trimmedTagline,
            git: MigrationGitSetup(
                initIfMissing: initGit,
                plumageInGit: plumageInGit,
                claudeInGit: claudeInGit,
                createGitignore: createGitignore))
    }

    // MARK: - Migrate (State-as-Bridge)

    func migrate() async {
        guard let spec = assembledSpec() else {
            error = Self.message(for: MigrateProjectError.incompleteForm)
            return
        }

        isMigrating = true
        error = nil
        defer { isMigrating = false }

        do {
            // Off-Main: the migrator does synchronous disk I/O and possibly a git
            // subprocess.
            let result = try await Task.detached(priority: .userInitiated) {
                try await ProjectMigrator().migrate(spec: spec)
            }.value
            // The driving Task is cancelled when the window closes mid-migration;
            // don't write back into an orphaned model.
            guard !Task.isCancelled else { return }
            migratedProject = result.0
            report = result.1
        } catch {
            guard !Task.isCancelled else { return }
            self.error = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? MigrateProjectError {
            switch error {
            case .incompleteForm:
                return "Some required information is missing."
            }
        }
        if let error = error as? ProjectMigrateError {
            switch error {
            case .alreadyPlumage:
                return "This folder is already a Plumage project. Open it instead."
            case .missingAssets:
                return "Project templates are missing from the app bundle. "
                    + "Try reinstalling Plumage."
            case .directoryMissing:
                return "The selected folder no longer exists."
            }
        }
        return error.localizedDescription
    }
}

nonisolated enum MigrateProjectError: Error, Equatable {
    case incompleteForm
}
