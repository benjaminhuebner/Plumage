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
    var planPermissionMode: PermissionMode?
    var implementPermissionMode: PermissionMode?
    var reviewPermissionMode: PermissionMode?
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
    // matches the spec ("disk write debounced (500 ms) against typing spam").
    static let debounceInterval: Duration = .milliseconds(500)

    private var pendingSaveTask: Task<Void, Never>?
    // Most-recently-started actual save. New saves chain off this so two
    // saves can never race on the disk write (last-writer-wins is fine,
    // overlapping reads aren't).
    private var inFlightSave: Task<Void, Never>?
    // Last loaded config so writes preserve the rest of the struct (name,
    // schemaVersion, git, …) intact when handing off to ConfigWriter.
    private var baseConfig: ProjectConfig?
    private let bundleURL: URL?

    // Injectable write callback so tests can drive the debounced path without
    // hitting disk. Sendable so the production path can actually offload the
    // I/O off MainActor — a previous @MainActor closure made the
    // `Task.detached` hop pointless (writer ran back on the main thread and
    // blocked the UI during disk I/O).
    private let writer: @Sendable (ProjectConfig, URL) throws -> Void
    // Fires after every successful save with the snapshot just persisted.
    // ProjectSettingsView wires this to an environment callback that
    // ProjectWindow uses to refresh ProjectModel.state and
    // TerminalTabsModel.modelsConfig — without it, picker changes hit disk
    // but live tabs keep spawning with the stale ModelsConfig.
    var onSaved: @MainActor (ProjectConfig) -> Void = { _ in }

    init(
        projectURL: URL,
        writer: @escaping @Sendable (ProjectConfig, URL) throws -> Void = { config, bundle in
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
        let planOverride = config.workflows?.plan
        let implementOverride = config.workflows?.implement
        let reviewOverride = config.workflows?.review
        planCommand = planOverride?.command.nilIfEmpty ?? Self.planDefault
        implementCommand = implementOverride?.command.nilIfEmpty ?? Self.implementDefault
        reviewCommand = reviewOverride?.command.nilIfEmpty ?? Self.reviewDefault
        planPermissionMode = planOverride?.permissionMode
        implementPermissionMode = implementOverride?.permissionMode
        reviewPermissionMode = reviewOverride?.permissionMode
        chatModel = config.models?.chat ?? ModelsConfig.chatDefault
        terminalsModel = config.models?.terminals ?? ModelsConfig.terminalsDefault
        planModel = config.models?.plan ?? ModelsConfig.planDefault
        implementModel = config.models?.implement ?? ModelsConfig.implementDefault
        reviewModel = config.models?.review ?? ModelsConfig.reviewDefault
    }

    // Default templates — used by the per-editor reset button and to detect
    // when a command override matches the built-in (so we skip writing to disk).
    static let planDefault = "/plumage-plan <slug><prompt-suffix>"
    static let implementDefault = "/plumage-implement <slug>"
    static let reviewDefault = "/plumage-review <slug>"

    // Edits are rejected when the load failed or hasn't completed yet — the
    // UI should disable inputs in those states, but this guard catches any
    // call site that slips through (e.g. an async refresh racing the load).
    var canEdit: Bool { loadState == .loaded }

    func resetCommand(for action: WorkflowAction) {
        guard canEdit else { return }
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
        guard canEdit else { return }
        switch action {
        case .plan: planCommand = value
        case .implement: implementCommand = value
        case .review: reviewCommand = value
        }
        scheduleSave()
    }

    func permissionMode(for action: WorkflowAction) -> PermissionMode? {
        switch action {
        case .plan: planPermissionMode
        case .implement: implementPermissionMode
        case .review: reviewPermissionMode
        }
    }

    func setPermissionMode(_ value: PermissionMode?, for action: WorkflowAction) {
        guard canEdit else { return }
        switch action {
        case .plan: planPermissionMode = value
        case .implement: implementPermissionMode = value
        case .review: reviewPermissionMode = value
        }
        // Picker selection is a discrete user choice; flush immediately so a
        // workflow click within the 500ms scheduleSave debounce can't spawn a
        // session with the old mode.
        Task { [weak self] in await self?.saveNow() }
    }

    // The action's built-in default permission mode — the one the picker
    // pre-selects and marks "(Default)" when no per-action override is set.
    // Model-independent: Plan is always plan-mode regardless of model choice.
    func resolvedFallbackMode(for action: WorkflowAction) -> PermissionMode {
        action.permissionMode
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
        guard canEdit else { return }
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

    // Clears the failed-save banner without scheduling another write — backs
    // the dismiss affordance on ProjectSettingsView's save-error banner so the
    // message isn't a sticky overlay the user can only clear by navigating away.
    func dismissSaveError() {
        if case .failed = saveStatus { saveStatus = .idle }
    }

    // Flush any pending debounced write immediately. Used by tests and by
    // contexts where we want a synchronous round-trip.
    func saveNow() async {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        await performSave()
    }

    private func performSave() async {
        // Chain off any in-flight save so reads + writes against disk
        // serialize. Without this, scheduleSave_B firing while
        // performSave_A's writer is still on the wire could let both writes
        // race the file (writer_B reads pre-A disk state and overwrites
        // writer_A's contribution).
        let prior = inFlightSave
        let task = Task { @MainActor in
            await prior?.value
            await self.doSave()
        }
        inFlightSave = task
        await task.value
    }

    private func doSave() async {
        guard let base = baseConfig, let bundle = bundleURL else {
            saveStatus = .failed(message: "Project bundle not available.")
            return
        }
        saveStatus = .saving
        let snapshot = mutated(from: base)
        let writer = self.writer
        do {
            // Detached + Sendable closure: actually runs off MainActor so
            // disk I/O doesn't block the UI. ConfigWriter.write is
            // nonisolated and ProjectConfig/URL are Sendable.
            try await Task.detached(priority: .userInitiated) {
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
            plan: workflowOverride(planCommand, default: Self.planDefault, mode: planPermissionMode),
            implement: workflowOverride(
                implementCommand, default: Self.implementDefault, mode: implementPermissionMode
            ),
            review: workflowOverride(reviewCommand, default: Self.reviewDefault, mode: reviewPermissionMode)
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

    // Returns nil when both command and mode are at their defaults — keeps
    // config.json clean and lets future Plumage default-changes apply without
    // per-project migration.
    private func workflowOverride(
        _ raw: String, default builtIn: String, mode: PermissionMode?
    ) -> WorkflowOverride? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandOverride = (trimmed.isEmpty || raw == builtIn) ? nil : raw
        if commandOverride == nil && mode == nil { return nil }
        return WorkflowOverride(command: commandOverride ?? "", permissionMode: mode)
    }

    private func nilIfSlotDefault(_ choice: ModelChoice, slot: ModelSlot) -> ModelChoice? {
        choice == ModelsConfig.slotDefault(for: slot) ? nil : choice
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
