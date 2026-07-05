import Foundation
import Observation
import SwiftUI
import os

@Observable
@MainActor
final class ProjectSettingsModel {
    enum SaveStatus: Sendable, Equatable {
        case idle
        case saving
        case saved
        case failed(message: String)
    }

    enum RenameStatus: Sendable, Equatable {
        case idle
        case renaming
        case failed(message: String)
    }

    let projectURL: URL

    private static let logger = Logger(subsystem: "com.plumage", category: "ProjectSettingsModel")

    private(set) var loadState: LoadState = .loading
    private(set) var saveStatus: SaveStatus = .idle
    private(set) var renameStatus: RenameStatus = .idle

    // Draft for the rename field. Seeded from config.name on load; the
    // "Rename…" button commits it. Kept separate from the debounced auto-save
    // fields below — a rename moves the bundle folder on disk and must NOT fire
    // on every keystroke, so it never goes through scheduleSave().
    var projectName: String = ""
    // The canonical on-disk name, used to detect when the draft actually
    // changed (button stays disabled until then).
    private(set) var currentName: String = ""

    // Plumage-owned mutable settings — every field round-trips through
    // ConfigWriter on commit(). View binds via @Bindable. The editors start
    // pre-filled with the spec'd default templates; per-slot models start at
    // ModelsConfig.slotDefault (Default = let the CLI resolve the model).
    var planCommand: String = ProjectSettingsModel.planDefault
    var implementCommand: String = ProjectSettingsModel.implementDefault
    var reviewCommand: String = ProjectSettingsModel.reviewDefault
    var planPermissionMode: PermissionMode?
    var implementPermissionMode: PermissionMode?
    var reviewPermissionMode: PermissionMode?
    var chatModel: ModelChoice = ModelsConfig.chatDefault
    var terminalsModel: ModelChoice = ModelsConfig.terminalsDefault
    // The app-wide type catalog, injected by the view before load(). The
    // per-type dicts below always carry exactly these types.
    private(set) var issueTypes: [IssueType] = IssueTypeCatalog.builtIn.types
    // Workflow slots are per-issue-type; the dicts always carry all catalog types.
    var planModels: [IssueType: ModelChoice] = [:]
    var implementModels: [IssueType: ModelChoice] = [:]
    var reviewModels: [IssueType: ModelChoice] = [:]
    var chatEffort: EffortLevel = EffortsConfig.chatDefault
    var terminalsEffort: EffortLevel = EffortsConfig.terminalsDefault
    var planEfforts: [IssueType: EffortLevel] = [:]
    var implementEfforts: [IssueType: EffortLevel] = [:]
    var reviewEfforts: [IssueType: EffortLevel] = [:]
    // The diff base. Seeded from config.gitDefaultBranch on load; a picker
    // choice saves immediately. Branch candidates load async for the picker.
    var defaultBranch: String = "main"
    private(set) var branchCandidates: [String] = []
    // Gates the default-branch picker: a non-git project has nothing to pick.
    private(set) var isGitRepo: Bool = true

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
    // var, not let: a successful rename moves the bundle folder, so the resolved
    // bundle path changes and every subsequent auto-save must target the new one.
    private var bundleURL: URL?

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
    // Fires after a successful rename with the reloaded config and the new
    // bundle URL. ProjectSettingsView wires this to an environment callback that
    // ProjectWindow uses to update the window title (config.name), repoint the
    // chat session's id-store to the moved bundle, and refresh Recents.
    var onRenamed: @MainActor (ProjectConfig, URL) -> Void = { _, _ in }

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
        let (result, repoIsGit): (Result<ProjectConfig, Error>, Bool) =
            await Task.detached(priority: .userInitiated) {
                let config: Result<ProjectConfig, Error>
                do {
                    config = .success(try ConfigLoader.load(at: url))
                } catch {
                    config = .failure(error)
                }
                return (config, RepoStateReader().read(repoURL: url).isGitRepo)
            }.value
        isGitRepo = repoIsGit
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
        currentName = config.name
        projectName = config.name
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
        planModels = workflowModels(from: config.models?.plan, slot: .planAction)
        implementModels = workflowModels(from: config.models?.implement, slot: .implementAction)
        reviewModels = workflowModels(from: config.models?.review, slot: .reviewAction)
        chatEffort = config.efforts?.chat ?? EffortsConfig.chatDefault
        terminalsEffort = config.efforts?.terminals ?? EffortsConfig.terminalsDefault
        planEfforts = workflowEfforts(from: config.efforts?.plan, slot: .planAction)
        implementEfforts = workflowEfforts(from: config.efforts?.implement, slot: .implementAction)
        reviewEfforts = workflowEfforts(from: config.efforts?.review, slot: .reviewAction)
        defaultBranch = config.gitDefaultBranch
    }

    // Re-completes the per-type dicts against a changed catalog: new types get
    // the slot default (or the uniform value when the slot is uniform), removed
    // types drop out. Called by the view before load() and on catalog changes.
    func setIssueTypes(_ types: [IssueType]) {
        guard types != issueTypes else { return }
        issueTypes = types
        planModels = recompleted(planModels, slot: .planAction)
        implementModels = recompleted(implementModels, slot: .implementAction)
        reviewModels = recompleted(reviewModels, slot: .reviewAction)
        planEfforts = recompletedEfforts(planEfforts, slot: .planAction)
        implementEfforts = recompletedEfforts(implementEfforts, slot: .implementAction)
        reviewEfforts = recompletedEfforts(reviewEfforts, slot: .reviewAction)
    }

    private func recompleted(
        _ map: [IssueType: ModelChoice], slot: ModelSlot
    ) -> [IssueType: ModelChoice] {
        let values = Set(map.values)
        let uniform = values.count == 1 ? values.first : nil
        let fill = uniform ?? ModelsConfig.slotDefault(for: slot)
        return Dictionary(uniqueKeysWithValues: issueTypes.map { ($0, map[$0] ?? fill) })
    }

    private func recompletedEfforts(
        _ map: [IssueType: EffortLevel], slot: ModelSlot
    ) -> [IssueType: EffortLevel] {
        let values = Set(map.values)
        let uniform = values.count == 1 ? values.first : nil
        let fill = uniform ?? EffortsConfig.slotDefault(for: slot)
        return Dictionary(uniqueKeysWithValues: issueTypes.map { ($0, map[$0] ?? fill) })
    }

    private func workflowModels(
        from setting: WorkflowModelSetting?, slot: ModelSlot
    ) -> [IssueType: ModelChoice] {
        let fallback = ModelsConfig.slotDefault(for: slot)
        return Dictionary(
            uniqueKeysWithValues: issueTypes.map {
                ($0, setting?.choice(for: $0) ?? fallback)
            })
    }

    private func workflowEfforts(
        from setting: WorkflowEffortSetting?, slot: ModelSlot
    ) -> [IssueType: EffortLevel] {
        let fallback = EffortsConfig.slotDefault(for: slot)
        return Dictionary(
            uniqueKeysWithValues: issueTypes.map {
                ($0, setting?.choice(for: $0) ?? fallback)
            })
    }

    // Default templates — used by the per-editor reset button and to detect
    // when a command override matches the built-in (so we skip writing to disk).
    static let planDefault = WorkflowCommandResolver.defaultCommand(for: .plan)
    static let implementDefault = WorkflowCommandResolver.defaultCommand(for: .implement)
    static let reviewDefault = WorkflowCommandResolver.defaultCommand(for: .review)

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

    // Model-owned bindings: every write funnels through the model's save
    // scheduling instead of ad-hoc Binding(get:set:) in the view body.
    var projectNameBinding: Binding<String> {
        Binding(
            get: { self.projectName },
            set: { self.projectName = $0 }
        )
    }

    func commandBinding(for action: WorkflowAction) -> Binding<String> {
        Binding(
            get: { self.command(for: action) },
            set: { self.setCommand($0, for: action) }
        )
    }

    func modelBinding(for slot: ModelSlot) -> Binding<ModelChoice> {
        Binding(
            get: { self.model(for: slot) },
            set: { self.setModel($0, for: slot) }
        )
    }

    func permissionModeBinding(for action: WorkflowAction) -> Binding<PermissionMode?> {
        Binding(
            get: { self.permissionMode(for: action) },
            set: { self.setPermissionMode($0, for: action) }
        )
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

    var defaultBranchBinding: Binding<String> {
        Binding(
            get: { self.defaultBranch },
            set: { self.setDefaultBranch($0) }
        )
    }

    func setDefaultBranch(_ value: String) {
        guard canEdit, value != defaultBranch else { return }
        defaultBranch = value
        // Discrete picker choice; flush now so a Diff tab opened right after
        // uses the new base instead of waiting on the 500ms debounce.
        Task { [weak self] in await self?.saveNow() }
    }

    func loadBranchCandidates() async {
        guard isGitRepo else {
            branchCandidates = []
            return
        }
        let url = projectURL
        branchCandidates = await Task.detached(priority: .userInitiated) {
            (try? await GitBranchLister().branches(repoURL: url)) ?? []
        }.value
    }

    // For workflow slots this is the collapsed-header value: the uniform
    // choice, or the slot default while the per-type values are mixed (the
    // view shows a "Mixed" indicator instead of trusting this value).
    func model(for slot: ModelSlot) -> ModelChoice {
        switch slot {
        case .chat: chatModel
        case .terminals: terminalsModel
        case .planAction, .implementAction, .reviewAction:
            uniformWorkflowModel(for: slot) ?? ModelsConfig.slotDefault(for: slot)
        }
    }

    // A pick on a workflow slot's collapsed header overwrites all four types.
    // Switching model also drops any effort the new model can't honour.
    func setModel(_ value: ModelChoice, for slot: ModelSlot) {
        guard canEdit else { return }
        switch slot {
        case .chat:
            chatModel = value
            chatEffort = clampedEffort(chatEffort, for: value)
        case .terminals:
            terminalsModel = value
            terminalsEffort = clampedEffort(terminalsEffort, for: value)
        case .planAction, .implementAction, .reviewAction:
            setWorkflowModels(uniform(value), for: slot)
            clampWorkflowEfforts(for: slot, model: value)
        }
        scheduleSave()
    }

    private func clampedEffort(_ effort: EffortLevel, for model: ModelChoice) -> EffortLevel {
        model.supportedEfforts.contains(effort) ? effort : .default
    }

    private func clampWorkflowEfforts(for slot: ModelSlot, model: ModelChoice) {
        var efforts = workflowEfforts(for: slot)
        for type in issueTypes {
            efforts[type] = clampedEffort(
                efforts[type] ?? EffortsConfig.slotDefault(for: slot),
                for: model
            )
        }
        setWorkflowEfforts(efforts, for: slot)
    }

    func workflowModels(for slot: ModelSlot) -> [IssueType: ModelChoice] {
        switch slot {
        case .planAction: planModels
        case .implementAction: implementModels
        case .reviewAction: reviewModels
        case .chat, .terminals: [:]
        }
    }

    func isWorkflowMixed(_ slot: ModelSlot) -> Bool {
        Set(workflowModels(for: slot).values).count > 1
    }

    func uniformWorkflowModel(for slot: ModelSlot) -> ModelChoice? {
        let values = Set(workflowModels(for: slot).values)
        return values.count == 1 ? values.first : nil
    }

    func workflowModelBinding(for slot: ModelSlot, type: IssueType) -> Binding<ModelChoice> {
        Binding(
            get: { self.workflowModels(for: slot)[type] ?? ModelsConfig.slotDefault(for: slot) },
            set: { self.setWorkflowModel($0, for: slot, type: type) }
        )
    }

    func setWorkflowModel(_ value: ModelChoice, for slot: ModelSlot, type: IssueType) {
        guard canEdit else { return }
        var models = workflowModels(for: slot)
        models[type] = value
        setWorkflowModels(models, for: slot)
        var efforts = workflowEfforts(for: slot)
        efforts[type] = clampedEffort(
            efforts[type] ?? EffortsConfig.slotDefault(for: slot),
            for: value
        )
        setWorkflowEfforts(efforts, for: slot)
        scheduleSave()
    }

    private func setWorkflowModels(_ models: [IssueType: ModelChoice], for slot: ModelSlot) {
        switch slot {
        case .planAction: planModels = models
        case .implementAction: implementModels = models
        case .reviewAction: reviewModels = models
        case .chat, .terminals: break
        }
    }

    private func uniform(_ value: ModelChoice) -> [IssueType: ModelChoice] {
        Dictionary(uniqueKeysWithValues: issueTypes.map { ($0, value) })
    }

    func effortBinding(for slot: ModelSlot) -> Binding<EffortLevel> {
        Binding(
            get: { self.effort(for: slot) },
            set: { self.setEffort($0, for: slot) }
        )
    }

    func effort(for slot: ModelSlot) -> EffortLevel {
        switch slot {
        case .chat: chatEffort
        case .terminals: terminalsEffort
        case .planAction, .implementAction, .reviewAction:
            uniformWorkflowEffort(for: slot) ?? EffortsConfig.slotDefault(for: slot)
        }
    }

    func setEffort(_ value: EffortLevel, for slot: ModelSlot) {
        guard canEdit else { return }
        switch slot {
        case .chat: chatEffort = value
        case .terminals: terminalsEffort = value
        case .planAction, .implementAction, .reviewAction:
            setWorkflowEfforts(uniformEffort(value), for: slot)
        }
        scheduleSave()
    }

    func workflowEfforts(for slot: ModelSlot) -> [IssueType: EffortLevel] {
        switch slot {
        case .planAction: planEfforts
        case .implementAction: implementEfforts
        case .reviewAction: reviewEfforts
        case .chat, .terminals: [:]
        }
    }

    func isWorkflowEffortMixed(_ slot: ModelSlot) -> Bool {
        Set(workflowEfforts(for: slot).values).count > 1
    }

    func uniformWorkflowEffort(for slot: ModelSlot) -> EffortLevel? {
        let values = Set(workflowEfforts(for: slot).values)
        return values.count == 1 ? values.first : nil
    }

    func workflowEffortBinding(for slot: ModelSlot, type: IssueType) -> Binding<EffortLevel> {
        Binding(
            get: { self.workflowEfforts(for: slot)[type] ?? EffortsConfig.slotDefault(for: slot) },
            set: { self.setWorkflowEffort($0, for: slot, type: type) }
        )
    }

    func setWorkflowEffort(_ value: EffortLevel, for slot: ModelSlot, type: IssueType) {
        guard canEdit else { return }
        var efforts = workflowEfforts(for: slot)
        efforts[type] = value
        setWorkflowEfforts(efforts, for: slot)
        scheduleSave()
    }

    private func setWorkflowEfforts(_ efforts: [IssueType: EffortLevel], for slot: ModelSlot) {
        switch slot {
        case .planAction: planEfforts = efforts
        case .implementAction: implementEfforts = efforts
        case .reviewAction: reviewEfforts = efforts
        case .chat, .terminals: break
        }
    }

    private func uniformEffort(_ value: EffortLevel) -> [IssueType: EffortLevel] {
        Dictionary(uniqueKeysWithValues: issueTypes.map { ($0, value) })
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

    // MARK: - Rename

    var trimmedProjectName: String {
        projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // The "Rename…" button is active only when the draft is a valid bundle name
    // AND actually differs from the on-disk name — renaming to the same name is
    // a no-op the UI shouldn't offer.
    var canRename: Bool {
        guard canEdit, renameStatus != .renaming else { return false }
        return BundleNameRules.isValid(projectName) && trimmedProjectName != currentName
    }

    func dismissRenameError() {
        if case .failed = renameStatus { renameStatus = .idle }
    }

    // Commits the rename. Moves the `<name>.plumage` bundle and rewrites
    // config.name off-main (ProjectRenamer is nonisolated, synchronous disk
    // I/O), then reloads config from the moved bundle so baseConfig + bundleURL
    // track the new location for subsequent auto-saves. On success fires
    // onRenamed so the window can update its title, repoint the chat session,
    // and refresh Recents.
    func rename() async {
        guard canRename else { return }
        let root = projectURL
        let newName = trimmedProjectName

        // Flush any debounced auto-save first so pending workflow/model edits
        // land in the bundle BEFORE it moves — otherwise the write would target
        // the old, now-gone path.
        await saveNow()

        renameStatus = .renaming
        let result: Result<(ProjectConfig, URL), Error> = await Task.detached(
            priority: .userInitiated
        ) {
            do {
                let newBundle = try ProjectRenamer.rename(projectRoot: root, newName: newName)
                let config = try ConfigLoader.load(atBundle: newBundle)
                return .success((config, newBundle))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let (config, newBundle)):
            baseConfig = config
            bundleURL = newBundle
            currentName = config.name
            projectName = config.name
            renameStatus = .idle
            onRenamed(config, newBundle)
        case .failure(let error):
            renameStatus = .failed(message: Self.renameMessage(for: error))
        }
    }

    static func renameMessage(for error: Error) -> String {
        guard let error = error as? ProjectRenamer.RenameError else {
            return error.localizedDescription
        }
        switch error {
        case .invalidName:
            return "That name isn't a valid folder name. Avoid “/”, “.”, and “..”."
        case .bundleExists(let url):
            return "A project named “\(url.deletingPathExtension().lastPathComponent)” already exists here."
        case .resolveFailed:
            return "Couldn't locate this project's .plumage bundle to rename."
        case .moveFailed(let message):
            return "Couldn't rename the project folder: \(message)"
        case .configWriteFailed(let message):
            return "Renamed the folder but couldn't update config.json: \(message)"
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
        // Chain off any in-flight save so reads + writes against disk
        // serialize. Without this, scheduleSave_B firing while
        // performSave_A's writer is still on the wire could let both writes
        // race the file (writer_B reads pre-A disk state and overwrites
        // writer_A's contribution).
        let prior = inFlightSave
        // [weak self]: a chained save can outlive the settings view; without it
        // the task would keep the model alive and write through a stale bundleURL
        // after a rename moved the bundle.
        let task = Task { @MainActor [weak self] in
            await prior?.value
            await self?.doSave()
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
            // A teardown flush (onDisappear) writes after the banner overlay is
            // gone, so log too — the failed status alone would go unseen there.
            Self.logger.warning("settings save failed: \(error.localizedDescription, privacy: .public)")
            saveStatus = .failed(message: error.localizedDescription)
        }
    }

    private func mutated(from base: ProjectConfig) -> ProjectConfig {
        var copy = base
        // Only defaultBranch is editable here; githubAccountID rides along so
        // the snapshot stays whole (ConfigWriter persists just defaultBranch).
        copy.git = GitConfig(defaultBranch: defaultBranch, githubAccountID: base.git?.githubAccountID)
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
            plan: workflowSetting(planModels, slot: .planAction),
            implement: workflowSetting(implementModels, slot: .implementAction),
            review: workflowSetting(reviewModels, slot: .reviewAction)
        )
        if copy.models == ModelsConfig() { copy.models = nil }
        copy.efforts = EffortsConfig(
            chat: nilIfEffortSlotDefault(chatEffort, slot: .chat),
            terminals: nilIfEffortSlotDefault(terminalsEffort, slot: .terminals),
            plan: workflowEffortSetting(planEfforts, slot: .planAction),
            implement: workflowEffortSetting(implementEfforts, slot: .implementAction),
            review: workflowEffortSetting(reviewEfforts, slot: .reviewAction)
        )
        if copy.efforts == EffortsConfig() { copy.efforts = nil }
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

    // All-identical maps collapse to the string form; an all-default slot is
    // elided from disk entirely, like the plain slots.
    private func workflowSetting(
        _ models: [IssueType: ModelChoice], slot: ModelSlot
    ) -> WorkflowModelSetting? {
        let normalized = WorkflowModelSetting.perType(models).normalized(for: issueTypes)
        if normalized == .uniform(ModelsConfig.slotDefault(for: slot)) { return nil }
        return normalized
    }

    private func nilIfEffortSlotDefault(_ level: EffortLevel, slot: ModelSlot) -> EffortLevel? {
        level == EffortsConfig.slotDefault(for: slot) ? nil : level
    }

    private func workflowEffortSetting(
        _ efforts: [IssueType: EffortLevel], slot: ModelSlot
    ) -> WorkflowEffortSetting? {
        let normalized = WorkflowEffortSetting.perType(efforts).normalized(for: issueTypes)
        if normalized == .uniform(EffortsConfig.slotDefault(for: slot)) { return nil }
        return normalized
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
