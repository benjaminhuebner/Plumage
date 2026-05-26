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
    // ConfigWriter on commit(). View binds via @Bindable.
    var planCommand: String = ""
    var implementCommand: String = ""
    var reviewCommand: String = ""
    var chatModel: ModelChoice = .default
    var terminalsModel: ModelChoice = .default
    var planModel: ModelChoice = .default
    var implementModel: ModelChoice = .default
    var reviewModel: ModelChoice = .default

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
        planCommand = config.workflows?.plan?.command ?? ""
        implementCommand = config.workflows?.implement?.command ?? ""
        reviewCommand = config.workflows?.review?.command ?? ""
        chatModel = config.models?.chat ?? .default
        terminalsModel = config.models?.terminals ?? .default
        planModel = config.models?.plan ?? .default
        implementModel = config.models?.implement ?? .default
        reviewModel = config.models?.review ?? .default
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
        } catch {
            saveStatus = .failed(message: error.localizedDescription)
        }
    }

    private func mutated(from base: ProjectConfig) -> ProjectConfig {
        var copy = base
        copy.workflows = WorkflowsConfig(
            plan: override(planCommand),
            implement: override(implementCommand),
            review: override(reviewCommand)
        )
        if copy.workflows == WorkflowsConfig() { copy.workflows = nil }
        copy.models = ModelsConfig(
            chat: nilForDefault(chatModel),
            terminals: nilForDefault(terminalsModel),
            plan: nilForDefault(planModel),
            implement: nilForDefault(implementModel),
            review: nilForDefault(reviewModel)
        )
        if copy.models == ModelsConfig() { copy.models = nil }
        return copy
    }

    private func override(_ raw: String) -> WorkflowOverride? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : WorkflowOverride(command: raw)
    }

    private func nilForDefault(_ choice: ModelChoice) -> ModelChoice? {
        choice == .default ? nil : choice
    }
}

nonisolated enum ModelSlot: Sendable, Hashable, CaseIterable {
    case chat
    case terminals
    case planAction
    case implementAction
    case reviewAction

    var label: String {
        switch self {
        case .chat: "Chat"
        case .terminals: "Terminals"
        case .planAction: "Plan Button"
        case .implementAction: "Implement Button"
        case .reviewAction: "Review Button"
        }
    }
}
