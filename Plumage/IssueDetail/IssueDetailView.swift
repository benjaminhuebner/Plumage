import AppKit
import CodeEditorView
import LanguageSupport
import SwiftUI

struct IssueDetailView: View {
    let projectURL: URL

    @State private var model: IssueDetailModel
    @State private var diffTabModel: DiffTabModel?
    @State private var gitRepoWatcher: GitRepoWatcher?
    // Each editable tab keeps its own cursor/scroll state so switching tabs
    // doesn't drag row 80 of a 200-line spec into a 2-line prompt and vice
    // versa. Messages are tab-scoped too in case a future hook re-wires
    // FrontmatterMessageMap markers into one of them.
    @State private var specEditorPosition = CodeEditor.Position()
    @State private var specEditorMessages: Set<TextLocated<Message>> = []
    @State private var hasAppliedSmartDefaultTab: Bool = false
    @State private var pendingSaveAlert: SaveAlert?
    @State private var saveAlertVisible: Bool = false
    @State private var pendingPopAction: (() -> Void)?
    // Cached focused-scene values. Computing these inline produces a new
    // value (or new closure) per body re-eval, which SwiftUI's focus system
    // flags as "FocusedValue update tried to update multiple times per
    // frame" when keystrokes / edits trigger cascading state changes. We
    // snapshot via .onChange so the focusedSceneValue modifiers read stable
    // identities.
    @State private var publishedDirtyFolderName: String?
    // Method-reference closures get a fresh allocation per body re-eval.
    // Wrapped in EditorAction (UUID-keyed Equatable) so the focus system
    // can compare stable identity across renders — without this the
    // `() -> Void` value type is always "different" and triggers
    // "FocusedValue update tried to update multiple times per frame".
    @State private var publishedSaveAction: EditorAction?
    @State private var publishedCloseAction: EditorAction?
    @State private var publishedBackToBoardAction: EditorAction?

    private let markdownLanguage = LanguageConfiguration.markdown()
    // Hides the right-edge minimap so the body editor uses the full width.
    private let editorLayout = CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSpec) private var openSpec
    @Environment(\.dismissToOrigin) private var dismissToOrigin
    @Environment(\.runWorkflow) private var runWorkflow
    @Environment(\.onIssueCreated) private var onIssueCreated
    @Environment(ProjectKanbanModel.self) private var kanban

    init(projectURL: URL, folderName: String) {
        self.projectURL = projectURL
        let specURL = IssueLayout.specURL(in: projectURL, folderName: folderName)
        _model = State(
            initialValue: IssueDetailModel(
                specURL: specURL, folderName: folderName, projectURL: projectURL
            )
        )
    }

    init(projectURL: URL, initialStatus: IssueStatus) {
        self.projectURL = projectURL
        _model = State(
            initialValue: IssueDetailModel(
                creatingInitialStatus: initialStatus, projectURL: projectURL
            )
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
            Image("FeatherGlyph")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.tertiary)
                .opacity(0.18)
                .padding(.top, 16)
                .padding(.trailing, 16)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundTint)
        .navigationTitle(model.navigationTitle)
        .focusedSceneValue(\.specEditorIsActive, true)
        .focusedSceneValue(\.specEditorSave, publishedSaveAction)
        .focusedSceneValue(\.specEditorClose, publishedCloseAction)
        .focusedSceneValue(\.specEditorDirtyFolderName, publishedDirtyFolderName)
        .focusedSceneValue(\.issueDetailBackToBoard, publishedBackToBoardAction)
        .task(id: model.specURL) {
            if publishedSaveAction == nil {
                publishedSaveAction = EditorAction { attemptSave() }
                publishedCloseAction = EditorAction { triggerPop() }
            }
            refreshBackToBoardCache()
            guard !model.isCreating else { return }
            await model.load()
            await model.loadPrompt()
            await model.loadPR()
            applySmartDefaultTabIfNeeded()
            refreshEditorMessages()
            refreshDirtyCache()
            startDiffTab()
        }
        .onChange(of: dismissToOrigin == nil) { _, _ in refreshBackToBoardCache() }
        .onChange(of: model.loadedSpecContent) { _, _ in refreshDirtyCache() }
        .onChange(of: model.loadedBodyContent) { _, _ in refreshDirtyCache() }
        .onChange(of: model.bodyDraft) { _, _ in refreshDirtyCache() }
        .onChange(of: model.loadedPromptContent) { _, _ in refreshDirtyCache() }
        .onChange(of: model.promptDraft) { _, _ in refreshDirtyCache() }
        .onChange(of: model.frontmatterError) { _, _ in refreshEditorMessages() }
        .onChange(of: currentKanbanIssue) { _, current in
            model.observeKanban(currentIssue: current)
        }
        .onChange(of: kanban.lastRemovalCompleted) { _, completed in
            if let completed, completed == model.folderName { popToBoard() }
        }
        .onChange(of: kanban.lastMergeCompleted) { _, completed in
            if let completed, completed == model.folderName { popToBoard() }
        }
        .onChange(of: model.conflict) { _, conflict in
            if conflict == .fileDeleted { popToBoard() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Auto-save on background only applies in loaded mode. In creating
            // mode there is no disk state yet — Cmd-W / back-nav dismisses
            // without persisting (per spec: keine Disk-Spur).
            if phase != .active && !model.isCreating { attemptSave() }
        }
        .alert(
            "Failed to save",
            isPresented: $saveAlertVisible,
            presenting: pendingSaveAlert
        ) { alert in
            switch alert.kind {
            case .pop:
                let popAction = pendingPopAction ?? { dismiss() }
                Button("Try again") { Task { await attemptPop(endAction: popAction) } }
                Button("Discard changes", role: .destructive) { popAction() }
            case .saveOnly:
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .onDisappear {
            model.cancelPendingWork()
            diffTabModel?.stop()
        }
    }

    // dismiss() is a no-op when this view is the split-view detail (nothing
    // is presented there), and openSpec defaults to a no-op inside the create
    // sheet (deliberately unwired). Firing both means exactly one acts in
    // either context.
    private func popToBoard() {
        openSpec(.kanban)
        dismiss()
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle:
            ProgressView().controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if model.isCreating || model.issue != nil {
                renderedDetail()
            } else {
                Text("Issue could not be parsed.")
                    .foregroundStyle(.secondary)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func renderedDetail() -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            compactHeader
            if model.isCreating {
                SpecTabView(
                    text: $model.bodyDraft,
                    position: $specEditorPosition,
                    messages: $specEditorMessages,
                    language: markdownLanguage,
                    layout: editorLayout
                )
                .toolbar {
                    // Gated on isCreating so the pushed loaded-mode detail
                    // (NavigatorDetail) never inherits these sheet buttons.
                    // .cancellationAction / .confirmationAction give macOS the
                    // bottom button row: Cancel left, prominent default Create
                    // Issue right — no manual styling needed.
                    if model.isCreating {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create Issue") { createAndNavigate() }
                                .buttonStyle(.borderedProminent)
                                // Override the default button's implicit plain
                                // Return: the sheet body is a multiline spec
                                // editor where Return must insert a newline.
                                .keyboardShortcut(.return, modifiers: [.command])
                                .disabled(!model.canSaveInCreatingMode)
                        }
                    }
                }
            } else {
                tabBody
            }
        }
    }

    // Single creation path: footer button (Cmd+Return) AND attemptSave (Cmd+S)
    // funnel through here so the sheet always dismisses + navigates to the new
    // issue on success. Splitting these two paths previously left Cmd+S in a
    // half-created state (issue on disk, sheet still open in loaded-mode UI).
    private func createAndNavigate() {
        Task {
            do {
                try await model.createIssueFromDraft()
                if let folderName = model.folderName {
                    onIssueCreated(folderName)
                    dismiss()
                }
            } catch IssueDetailModel.SaveError.emptyTitle {
                // Gated by canSaveInCreatingMode; no alert needed.
            } catch {
                presentSaveAlert(message: error.localizedDescription, kind: .saveOnly)
            }
        }
    }

    @ViewBuilder
    private var compactHeader: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if !model.isCreating {
                IssueDetailBanner(
                    frontmatterError: model.frontmatterError,
                    conflict: model.conflict,
                    onReload: { model.resolveConflictReload() },
                    onKeep: { model.resolveConflictKeep() }
                )
            }
            IssueDetailTopBar(
                paddedID: paddedID,
                branch: branch,
                showsCopyID: !model.isCreating,
                isCreating: model.isCreating,
                saveDisabled: saveDisabled,
                onCopyID: model.copyIDToPasteboard,
                onSave: attemptSave
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            IssueTitleRow(
                titleDraft: $model.titleDraft,
                titlePlaceholder: model.isCreating ? "Issue title" : "Title",
                autoFocusTitle: model.isCreating,
                onCommitTitle: onCommitTitle,
                isDisabled: detailFieldsDisabled,
                workflowBar: workflowBarConfig
            )
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 6)
            IssueMetaRow(
                status: currentStatus,
                type: currentType,
                labels: currentLabels,
                dates: metaDates,
                onSelectStatus: onSelectStatus,
                onSelectType: onSelectType,
                onAddLabel: onAddLabel,
                onRemoveLabel: onRemoveLabel,
                isDisabled: detailFieldsDisabled
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            if !model.isCreating {
                BodyTabPicker(selectedTab: $model.selectedBodyTab)
                    .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        @Bindable var model = model
        switch model.selectedBodyTab {
        case .prompt:
            PromptTabView(text: $model.promptDraft)
        case .spec:
            SpecTabView(
                text: $model.bodyDraft,
                position: $specEditorPosition,
                messages: $specEditorMessages,
                language: markdownLanguage,
                layout: editorLayout
            )
        case .pullRequest:
            VStack(alignment: .leading, spacing: 12) {
                PRTabView(blocks: model.prBlocks)
                    .task(id: model.selectedBodyTab) {
                        // Reload-on-show: PR.md changes externally (e.g.
                        // /plumage-implement just wrote it), and the tab is
                        // read-only so there's no dirty-conflict to worry about.
                        if model.selectedBodyTab == .pullRequest {
                            await model.loadPR()
                        }
                    }
                if currentStatus == .waitingForReview, let issue = model.issue {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        MergeBranchSection(
                            branch: issue.branch,
                            subjectPrefill: model.mergeSubjectPrefill,
                            isMerging: model.isMerging,
                            errorMessage: mergeBannerMessage,
                            nonFatalNotice: model.lastMergeNotice,
                            onDismissError: {
                                model.clearMergeError()
                                model.clearMergeCriticalError()
                            },
                            onDismissNotice: { model.clearMergeNotice() },
                            onMerge: { mode, commitSubject, deleteBranch in
                                Task {
                                    await performMerge(
                                        mode: mode,
                                        commitSubject: commitSubject,
                                        deleteBranch: deleteBranch)
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .diff:
            if let diffTabModel {
                DiffTabView(model: diffTabModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var backgroundTint: some View {
        let color = currentType.color
        return LinearGradient(
            colors: [
                color.opacity(0.10),
                Color(NSColor.windowBackgroundColor),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Mode-aware data sources

    private var currentKanbanIssue: DiscoveredIssue? {
        // Project the single kanban entry this view cares about so .onChange
        // doesn't fire on every unrelated snapshot. Cheap: O(n) once per
        // kanban update, vs. O(n) per render via .onChange(of: kanban.issues).
        guard let folder = model.folderName else { return nil }
        return kanban.issues.first { $0.id == folder }
    }

    private var currentStatus: IssueStatus {
        if model.isCreating { return model.statusDraft }
        return model.issue?.status ?? model.statusDraft
    }

    private var currentType: IssueType {
        if model.isCreating { return model.typeDraft }
        return model.issue?.type ?? model.typeDraft
    }

    private var currentLabels: [String] {
        if model.isCreating { return model.labelsDraft }
        return model.issue?.labels ?? []
    }

    private var metaDates: IssueMetaRow.Dates? {
        guard let issue = model.issue else { return nil }
        return .init(created: issue.created, updated: issue.updated)
    }

    private var workflowBarConfig: IssueTitleRow.WorkflowBarConfig? {
        guard !model.isCreating, let folderName = model.folderName else { return nil }
        return .init(
            status: currentStatus,
            type: currentType,
            runWorkflow: { action in triggerWorkflow(action, folderName: folderName) }
        )
    }

    private var paddedID: String? {
        guard !model.isCreating, let issue = model.issue else { return nil }
        return "#" + IssueIDFormatter.padded(issue.id, width: 5)
    }

    private var branch: String? {
        guard !model.isCreating, let issue = model.issue else { return nil }
        return issue.branch
    }

    private var saveDisabled: Bool {
        if model.isCreating { return !model.canSaveInCreatingMode }
        return false
    }

    private var detailFieldsDisabled: Bool {
        if model.isCreating { return false }
        return model.frontmatterError != nil
    }

    // MARK: - Mode-aware callbacks

    private func onCommitTitle() {
        // In creating mode, the title lives entirely in `model.titleDraft`
        // until save; no per-keystroke commit. In loaded mode, on-blur
        // writes through to disk.
        guard !model.isCreating else { return }
        runFormCommit { try await model.commitTitle(model.titleDraft) }
    }

    private func onAddLabel(_ newLabel: String) {
        if model.isCreating {
            if !model.labelsDraft.contains(newLabel) {
                model.labelsDraft.append(newLabel)
            }
            return
        }
        guard let issue = model.issue else { return }
        let next = issue.labels + [newLabel]
        runFormCommit { try await model.commitLabels(next) }
    }

    private func onRemoveLabel(_ label: String) {
        if model.isCreating {
            model.labelsDraft.removeAll { $0 == label }
            return
        }
        guard let issue = model.issue else { return }
        let next = issue.labels.filter { $0 != label }
        runFormCommit { try await model.commitLabels(next) }
    }

    private func onSelectType(_ newType: IssueType) {
        if model.isCreating {
            model.typeDraft = newType
            return
        }
        runFormCommit { try await model.commitType(newType) }
    }

    private func onSelectStatus(_ newStatus: IssueStatus) {
        if model.isCreating {
            model.statusDraft = newStatus
            return
        }
        runFormCommit { try await model.commitStatus(newStatus) }
    }

    private func refreshEditorMessages() {
        // Frontmatter error markers point into the raw spec — the tabbed
        // body editor only renders the body, so the markers have no row to
        // attach to here. The error banner above still surfaces the issue.
        if !specEditorMessages.isEmpty { specEditorMessages = [] }
    }

    private func refreshDirtyCache() {
        let next = model.dirtyFolderName()
        if publishedDirtyFolderName != next {
            publishedDirtyFolderName = next
        }
    }

    private func applySmartDefaultTabIfNeeded() {
        // Only on the very first load per view lifetime, so reopening the
        // same card doesn't snap the user's deliberate tab choice back to
        // the status-driven default.
        guard !hasAppliedSmartDefaultTab else { return }
        guard let issue = model.issue else { return }
        hasAppliedSmartDefaultTab = true
        model.selectedBodyTab = IssueDetailModel.defaultTab(for: issue.status)
    }

    private func startDiffTab() {
        // The card is the unit of cache here: every open spins up a fresh
        // DiffTabModel + GitRepoWatcher so the diff and the live-update
        // signal are scoped to this card's lifetime (see spec scope: no
        // cross-card diff cache).
        guard diffTabModel == nil else { return }
        let watcher = GitRepoWatcher(repoURL: projectURL)
        let diffModel = DiffTabModel(repoURL: projectURL, watcher: watcher)
        gitRepoWatcher = watcher
        diffTabModel = diffModel
        diffModel.start()
    }

    private func refreshBackToBoardCache() {
        let hasOrigin = dismissToOrigin != nil
        let isCached = publishedBackToBoardAction != nil
        if hasOrigin && !isCached {
            publishedBackToBoardAction = EditorAction {
                if let action = dismissToOrigin {
                    triggerBack(action)
                }
            }
        } else if !hasOrigin && isCached {
            publishedBackToBoardAction = nil
        }
    }

    private var mergeBannerMessage: String? {
        if let critical = model.lastMergeCriticalError { return critical }
        if let error = model.lastMergeError { return error.displayMessage }
        return nil
    }

    private func performMerge(
        mode: GitMergeMode, commitSubject: String?, deleteBranch: Bool
    ) async {
        let success = await model.mergeToMain(
            mode: mode, commitSubject: commitSubject, deleteBranch: deleteBranch)
        guard success, let folderName = model.folderName else { return }
        kanban.signalMergeCompleted(folderName: folderName)
    }

    private func runFormCommit(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                presentSaveAlert(message: error.localizedDescription, kind: .saveOnly)
            }
        }
    }

    private func attemptSave() {
        // Fire-and-forget: IssueDetailModel serializes overlapping save calls
        // on its own pending chains, so a rapid double-click of Save just
        // queues a no-op (guard-by-dirty) after the in-flight write finishes.
        if model.isCreating {
            guard model.canSaveInCreatingMode else { return }
            createAndNavigate()
            return
        }
        Task {
            do {
                try await saveAllEditableTabs()
            } catch {
                presentSaveAlert(message: error.localizedDescription, kind: .saveOnly)
            }
        }
    }

    private func saveAllEditableTabs() async throws {
        // Flush both editable buffers regardless of the currently-selected
        // tab. Otherwise dirty Spec/Prompt content sitting behind a non-
        // editable tab (PR, Diff) would be silently dropped on background
        // autosave or Cmd-S. The model's per-buffer dirty guards keep this
        // cheap when nothing changed.
        var firstError: Error?
        do { try await model.saveBody() } catch { firstError = firstError ?? error }
        do { try await model.savePrompt() } catch { firstError = firstError ?? error }
        if let firstError { throw firstError }
    }

    private func triggerWorkflow(_ action: WorkflowAction, folderName: String) {
        // WorkflowCommandResolver reads spec.md and prompt.md from disk, so
        // both dirty buffers must be flushed before the inject runs. If a flush
        // fails, surface it and abort — injecting the stale on-disk version into
        // claude with no indication would silently run the workflow on outdated
        // content.
        Task {
            do {
                try await saveAllEditableTabs()
            } catch {
                presentSaveAlert(message: error.localizedDescription, kind: .saveOnly)
                return
            }
            runWorkflow(action, folderName)
        }
    }

    private func triggerPop() {
        Task { await attemptPop(endAction: { dismiss() }) }
    }

    private func triggerBack(_ action: @escaping () -> Void) {
        Task { await attemptPop(endAction: action) }
    }

    private func attemptPop(endAction: @escaping () -> Void) async {
        // Creating mode never has unsaved disk state: closing leaves no
        // trace and the in-memory drafts go away with the view.
        if model.isCreating {
            endAction()
            return
        }
        do {
            // Flush both editable tabs. saveAllEditableTabs runs both saves
            // even if one fails, so a failing body save doesn't strand a
            // dirty prompt buffer (or vice versa).
            try await saveAllEditableTabs()
            endAction()
        } catch {
            pendingPopAction = endAction
            presentSaveAlert(message: error.localizedDescription, kind: .pop)
        }
    }

    private func presentSaveAlert(message: String, kind: SaveAlert.Kind) {
        pendingSaveAlert = SaveAlert(message: message, kind: kind)
        saveAlertVisible = true
    }
}

#Preview {
    NavigationStack {
        IssueDetailView(
            projectURL: URL(filePath: "/tmp/sample"),
            folderName: "00016-better-issue-details"
        )
    }
    .environment(ProjectKanbanModel())
    .frame(width: 900, height: 700)
}
