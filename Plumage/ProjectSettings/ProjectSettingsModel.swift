import Foundation
import Observation

@Observable
@MainActor
final class ProjectSettingsModel {
    enum SaveStatus: Sendable, Equatable {
        case idle
        case saving
        case saved
        case failed(message: String)
    }

    let projectURL: URL

    private(set) var loadState: LoadState = .loading
    private(set) var saveStatus: SaveStatus = .idle

    // Plumage-owned mutable settings — every field round-trips through
    // ConfigWriter on commit(). View binds via @Bindable. The editors start
    // pre-filled with the spec'd default templates; per-slot models start at
    // ModelsConfig.slotDefault so users see concrete model names, not "Default".
    var planCommand: String = ProjectSettingsModel.planDefault
    var implementCommand: String = ProjectSettingsModel.implementDefault
    var reviewCommand: String = ProjectSettingsModel.reviewDefault
    var chatModel: ModelChoice = ModelsConfig.chatDefault
    var terminalsModel: ModelChoice = ModelsConfig.terminalsDefault
    var planModel: ModelChoice = ModelsConfig.planDefault
    var implementModel: ModelChoice = ModelsConfig.implementDefault
    var reviewModel: ModelChoice = ModelsConfig.reviewDefault

    enum LoadState: Sendable, Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    // Debounce window between the latest mutation and the disk write. 500ms
    // matches the spec ("Disk-Write debounced (500 ms) gegen Tipp-Spam.").
    static let debounceInterval: Duration = .milliseconds(500)

    private var pendingSaveTask: Task<Void, Never>?
    // Last loaded config so writes preserve every unknown top-level key —
    // ConfigWriter handles that, but we still need the rest of the struct
    // (name, schemaVersion, git, …) intact when handing off to it.
    private var baseConfig: ProjectConfig?
    private let bundleURL: URL?

    // Injectable write callback so tests can drive the debounced path without
    // hitting disk. Default uses ConfigWriter.write atomically.
    private let writer: @MainActor (ProjectConfig, URL) throws -> Void
    // Fires after every successful save with the snapshot just persisted.
    // ProjectSettingsView wires this to an environment callback that
    // ProjectWindow uses to refresh ProjectModel.state and
    // TerminalTabsModel.modelsConfig — without it, picker changes hit disk
    // but live tabs keep spawning with the stale ModelsConfig.
    var onSaved: @MainActor (ProjectConfig) -> Void = { _ in }

    init(
        projectURL: URL,
        writer: @escaping @MainActor (ProjectConfig, URL) throws -> Void = { config, bundle in
            try ConfigWriter.write(config, atBundle: bundle)
        }
    ) {
        self.projectURL = projectURL
        self.writer = writer
        self.bundleURL = try? BundleResolver.findBundle(in: projectURL)
    }

    func load() async {
        loadState = .loading
        let url = projectURL
        let result: Result<ProjectConfig, Error> = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try ConfigLoader.load(at: url))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let config):
            apply(config: config)
            loadState = .loaded
        case .failure(let error):
            loadState = .failed(message: error.localizedDescription)
        }
    }

    private func apply(config: ProjectConfig) {
        baseConfig = config
        // Override on disk → show that. No override → show the default template
        // so the user always sees what'll actually be injected.
        planCommand = config.workflows?.plan?.command ?? Self.planDefault
        implementCommand = config.workflows?.implement?.command ?? Self.implementDefault
        reviewCommand = config.workflows?.review?.command ?? Self.reviewDefault
        chatModel = config.models?.chat ?? ModelsConfig.chatDefault
        terminalsModel = config.models?.terminals ?? ModelsConfig.terminalsDefault
        planModel = config.models?.plan ?? ModelsConfig.planDefault
        implementModel = config.models?.implement ?? ModelsConfig.implementDefault
        reviewModel = config.models?.review ?? ModelsConfig.reviewDefault
    }

    // Default templates from the spec — used by the per-editor reset button.
    static let planDefault = "/plumage-plan <slug>\n<prompt>"
    static let implementDefault = "/plumage-implement <slug>"
    static let reviewDefault = "/plumage-review <slug>"

    func resetCommand(for action: WorkflowAction) {
        switch action {
        case .plan: planCommand = Self.planDefault
        case .implement: implementCommand = Self.implementDefault
        case .review: reviewCommand = Self.reviewDefault
        }
        scheduleSave()
    }

    func command(for action: WorkflowAction) -> String {
        switch action {
        case .plan: planCommand
        case .implement: implementCommand
        case .review: reviewCommand
        }
    }

    func setCommand(_ value: String, for action: WorkflowAction) {
        switch action {
        case .plan: planCommand = value
        case .implement: implementCommand = value
        case .review: reviewCommand = value
        }
        scheduleSave()
    }

    func model(for slot: ModelSlot) -> ModelChoice {
        switch slot {
        case .chat: chatModel
        case .terminals: terminalsModel
        case .planAction: planModel
        case .implementAction: implementModel
        case .reviewAction: reviewModel
        }
    }

    func setModel(_ value: ModelChoice, for slot: ModelSlot) {
        switch slot {
        case .chat: chatModel = value
        case .terminals: terminalsModel = value
        case .planAction: planModel = value
        case .implementAction: implementModel = value
        case .reviewAction: reviewModel = value
        }
        scheduleSave()
    }

    // Public for ProjectSettingsView's onChange driver — every field bound
    // via @Bindable funnels through this.
    func scheduleSave() {
        pendingSaveTask?.cancel()
        saveStatus = .idle
        pendingSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.performSave()
        }
    }

    // Flush any pending debounced write immediately. Used by tests and by
    // contexts where we want a synchronous round-trip.
    func saveNow() async {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        await performSave()
    }

    private func performSave() async {
        guard let base = baseConfig, let bundle = bundleURL else {
            saveStatus = .failed(message: "Project bundle not available.")
            return
        }
        saveStatus = .saving
        let snapshot = mutated(from: base)
        let writer = self.writer
        do {
            try await Task.detached(priority: .userInitiated) { @MainActor in
                try writer(snapshot, bundle)
            }.value
            baseConfig = snapshot
            saveStatus = .saved
            onSaved(snapshot)
        } catch {
            saveStatus = .failed(message: error.localizedDescription)
        }
    }

    private func mutated(from base: ProjectConfig) -> ProjectConfig {
        var copy = base
        copy.workflows = WorkflowsConfig(
            plan: override(planCommand, default: Self.planDefault),
            implement: override(implementCommand, default: Self.implementDefault),
            review: override(reviewCommand, default: Self.reviewDefault)
        )
        if copy.workflows == WorkflowsConfig() { copy.workflows = nil }
        copy.models = ModelsConfig(
            chat: nilIfSlotDefault(chatModel, slot: .chat),
            terminals: nilIfSlotDefault(terminalsModel, slot: .terminals),
            plan: nilIfSlotDefault(planModel, slot: .planAction),
            implement: nilIfSlotDefault(implementModel, slot: .implementAction),
            review: nilIfSlotDefault(reviewModel, slot: .reviewAction)
        )
        if copy.models == ModelsConfig() { copy.models = nil }
        return copy
    }

    // Save as nil when the editor content matches the spec default — keeps
    // config.json clean and lets a future Plumage default-change apply
    // automatically without per-project migration.
    private func override(_ raw: String, default builtIn: String) -> WorkflowOverride? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if raw == builtIn { return nil }
        return WorkflowOverride(command: raw)
    }

    private func nilIfSlotDefault(_ choice: ModelChoice, slot: ModelSlot) -> ModelChoice? {
        choice == ModelsConfig.slotDefault(for: slot) ? nil : choice
    }
}
