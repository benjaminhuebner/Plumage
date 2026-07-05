import AppKit
import CodeEditorView
import LanguageSupport
import SwiftUI

struct IssueDetailView: View {
    let projectURL: URL

    @State private var model: IssueDetailModel
    @State private var diffTabModel: DiffTabModel?
    @State private var reviewFindings: ReviewFindingsModel?
    @State private var gitRepoWatcher: GitRepoWatcher?
    // Each editable tab keeps its own cursor/scroll state so switching tabs
    // doesn't drag row 80 of a 200-line spec into a 2-line prompt and vice versa.
    // Messages are tab-scoped too in case a future hook re-wires markers into one.
    @State private var specEditorPosition = CodeEditor.Position()
    @State private var specEditorMessages: Set<TextLocated<Message>> = []
    @State private var hasAppliedSmartDefaultTab: Bool = false
    @State private var pendingSaveAlert: SaveAlert?
    @State private var saveAlertVisible: Bool = false
    // Cached focused-scene values: computing inline yields a new value per body
    // re-eval, which the focus system flags as "FocusedValue update tried to update
    // multiple times per frame". Snapshot via .onChange so identities stay stable.
    @State private var publishedDirtyFolderName: String?
    // Method-reference closures get a fresh allocation per body re-eval. Wrapped
    // in EditorAction (UUID-keyed Equatable) so the focus system compares stable
    // identity — otherwise it fires "FocusedValue update … multiple times per frame".
    @State private var publishedSaveAction: EditorAction?
    @State private var publishedCloseAction: EditorAction?
    @State private var publishedBackToBoardAction: EditorAction?
    @State private var quitFlushID = UUID()
    // Cached so the O(n×m) union+sort runs per board change, not per body eval.
    @State private var cachedExistingLabels: [String] = []
    @State private var cachedBlockerCandidates: [BlockerCandidate] = []

    private let markdownLanguage = LanguageConfiguration.markdown()
    // Hides the right-edge minimap so the body editor uses the full width.
    private let editorLayout = CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSpec) private var openSpec
    @Environment(\.dismissToOrigin) private var dismissToOrigin
    @Environment(\.runWorkflow) private var runWorkflow
    @Environment(\.jumpToRunTerminal) private var jumpToRunTerminal
    @Environment(\.onIssueCreated) private var onIssueCreated
    @Environment(\.issueTypeCatalog) private var issueTypeCatalog
    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(RunStatusModel.self) private var runStatus

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
            // ⌘Q doesn't run .onDisappear reliably; QuitCoordinator awaits
            // this flush. weak: the registry is app-lifetime and .onDisappear
            // (the only unregister) can be skipped — strong would pin the model.
            QuitCoordinator.shared.register(quitFlushID) { [weak model] in
                guard let model, !model.isCreating else { return }
                await model.autoSaveNow()
            }
            refreshBackToBoardCache()
            seedExistingLabels()
            seedBlockerCandidates()
            // New issues start on the catalog's configured default type.
            if model.isCreating {
                model.typeDraft = issueTypeCatalog.defaultType
            }
            guard !model.isCreating else { return }
            await model.load()
            await model.loadPrompt()
            await model.loadPR()
            applySmartDefaultTabIfNeeded()
            refreshEditorMessages()
            refreshDirtyCache()
            startDiffTab()
            await reviewFindings?.load()
        }
        .onChange(of: dismissToOrigin == nil) { _, _ in refreshBackToBoardCache() }
        .onChange(of: model.loadedSpecContent) { _, _ in refreshDirtyCache() }
        .onChange(of: model.loadedBodyContent) { _, _ in refreshDirtyCache() }
        .onChange(of: model.bodyDraft) { _, _ in handleEditorBufferChange() }
        .onChange(of: model.loadedPromptContent) { _, _ in refreshDirtyCache() }
        .onChange(of: model.promptDraft) { _, _ in handleEditorBufferChange() }
        .onChange(of: model.frontmatterError) { _, _ in refreshEditorMessages() }
        .onChange(of: currentKanbanIssue) { _, current in boardDidChange(current) }
        .onChange(of: kanban.lastRemovalCompleted) { _, completed in
            guard let completed, completed == model.folderName else { return }
            popToBoard()
            kanban.clearLastRemovalCompleted()
        }
        .onChange(of: kanban.lastMergeCompleted) { _, completed in
            guard let completed, completed == model.folderName else { return }
            popToBoard()
            kanban.clearLastMergeCompleted()
        }
        .onChange(of: model.conflict) { _, conflict in
            if conflict == .fileDeleted { popToBoard() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Auto-save on background only applies in loaded mode. In creating
            // mode there is no disk state yet — Cmd-W / back-nav dismisses
            // without persisting (per spec: keine Disk-Spur).
            if phase != .active && !model.isCreating { flushAutoSaveNow() }
        }
        .alert(
            "Failed to save",
            isPresented: $saveAlertVisible,
            presenting: pendingSaveAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .onDisappear {
            QuitCoordinator.shared.unregister(quitFlushID)
            // A sidebar route switch bypasses the pop flush; strong-capture so the
            // trailing write completes as the view releases its @State.
            Task { [model] in await model.autoSaveNow() }
            model.cancelPendingWork()
            diffTabModel?.stop()
        }
    }

    // dismiss() is a no-op when this view is the split-view detail, and openSpec
    // defaults to a no-op inside the create sheet (deliberately unwired). Firing
    // both means exactly one acts in either context.
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
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Try Again") {
                        Task {
                            await model.load()
                            await model.loadPrompt()
                            await model.loadPR()
                        }
                    }
                    Button("Back to Board") { popToBoard() }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    // Gated on isCreating so the pushed loaded-mode detail never
                    // inherits these sheet buttons. .cancellationAction /
                    // .confirmationAction give macOS the standard bottom button row.
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
    // funnel through here so the sheet always dismisses + navigates on success —
    // split paths left Cmd+S half-created (issue on disk, sheet still open).
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
                presentSaveAlert(message: error.localizedDescription)
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
                autoSaveStatus: model.autoSaveStatus,
                onCopyID: model.copyIDToPasteboard,
                onRetry: { Task { await model.autoSaveNow() } }
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
                availableTypes: issueTypeCatalog.types,
                labels: currentLabels,
                existingLabels: cachedExistingLabels,
                dates: metaDates,
                onSelectStatus: onSelectStatus,
                onSelectType: onSelectType,
                onAddLabel: onAddLabel,
                onRemoveLabel: onRemoveLabel,
                isDisabled: detailFieldsDisabled
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            if model.isCreating || model.issue != nil {
                BlockedByChipRow(
                    blockers: resolvedBlockers,
                    candidates: cachedBlockerCandidates,
                    onAdd: onAddBlocker,
                    onRemove: onRemoveBlocker,
                    onOpen: { openSpec(.issue(folderName: $0)) }
                )
                .disabled(detailFieldsDisabled)
                .padding(.horizontal, 16)
                .padding(.bottom, 5)
            }
            if let folderName = model.folderName,
                let run = runStatus.liveRuns[folderName]
            {
                RunStatusStrip(state: run.state, isWorktree: run.isWorktree) {
                    jumpToRunTerminal(folderName)
                }
            } else if let folderName = model.folderName,
                RunStatusModel.resumeAvailable(
                    status: currentStatus,
                    hasLiveRun: false,
                    isQueued: runStatus.queuedRuns.contains { $0.issue == folderName }
                )
            {
                ResumeRunStrip(
                    lastPhase: runStatus.runSnapshots.first { $0.slug == folderName }?.state.phase
                ) {
                    triggerWorkflow(.implement, folderName: folderName)
                }
            }
            if !model.isCreating {
                BodyTabPicker(selectedTab: model.bodyTabBinding, badgeCounts: tabBadgeCounts) {
                    if model.selectedBodyTab == .diff {
                        DiffViewModeToggle()
                            .transition(.opacity)
                    }
                }
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
            // One scroll surface for everything: rigid sections beside a nested
            // ScrollView overflowed the non-scrolling split-view detail and
            // blanked the whole window.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PRTabView(blocks: model.prBlocks)
                    if currentStatus == .waitingForReview, let issue = model.issue {
                        reviewSections(issue: issue)
                    }
                    if !model.runHistory.records.isEmpty {
                        Divider()
                        RunHistorySection(page: model.runHistory)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .task(id: model.selectedBodyTab) {
                // Reload-on-show: PR.md changes externally (e.g.
                // /plumage-implement just wrote it), and the tab is
                // read-only so there's no dirty-conflict to worry about.
                if model.selectedBodyTab == .pullRequest {
                    await model.loadPR()
                    await model.loadEvidence()
                    await model.loadRunHistory(roots: historyRoots)
                }
            }
            .onChange(of: runStatus.revision) {
                // A finished or swept run lands in history without a tab
                // switch; the watcher revision is the reload signal.
                if model.selectedBodyTab == .pullRequest {
                    Task { await model.loadRunHistory(roots: historyRoots) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .diff:
            if let diffTabModel {
                DiffTabView(model: diffTabModel, findings: reviewFindings)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var historyRoots: [URL] {
        runStatus.scannedRoots.isEmpty ? [projectURL] : runStatus.scannedRoots
    }

    @ViewBuilder
    private func reviewSections(issue: Issue) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            EvidenceSection(state: model.evidence, isStale: model.evidenceIsStale)
            if !model.doneWhenCriteria.isEmpty {
                DoneWhenChecklist(
                    criteria: model.doneWhenCriteria,
                    isDisabled: model.conflict != nil,
                    binding: { model.doneWhenBinding(at: $0) }
                )
            }
            if let reviewFindings {
                RequestChangesSection(
                    openCount: reviewFindings.openFindings.count,
                    isBusy: model.isRequestingChanges,
                    errorMessage: model.lastRequestChangesError,
                    onRequestChanges: { requestChanges() },
                    onDismissError: { model.clearRequestChangesError() }
                )
            }
            MergeBranchSection(
                branch: issue.branch,
                subjectPrefill: model.mergeSubjectPrefill,
                isMerging: model.isMerging,
                blockingRunIssue: model.blockingImplementRun?.issue,
                errorMessage: mergeBannerMessage,
                nonFatalNotice: model.lastMergeNotice,
                targetBranch: model.selectedMergeTarget ?? "main",
                targetCandidates: model.mergeTargets,
                onTargetChange: { model.selectedMergeTarget = $0 },
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
                },
                onRebaseAndMerge: rebaseAndMergeAction
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .task {
            await model.refreshMergeBlocker()
            await model.loadMergeTargets()
        }
        .onChange(of: runStatus.revision) {
            // The runs watcher replaces the former 3s poll: the button
            // re-enables on the FSEvent when the run-state leaves runs/.
            Task { await model.refreshMergeBlocker() }
        }
    }

    private var backgroundTint: some View {
        let color = issueTypeCatalog.color(for: currentType)
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

    private var currentStatus: IssueStatus {
        if model.isCreating {
            model.statusDraft
        } else {
            model.issue?.status ?? model.statusDraft
        }
    }

    private var currentType: IssueType {
        if model.isCreating {
            model.typeDraft
        } else {
            model.issue?.type ?? model.typeDraft
        }
    }

    private var currentLabels: [String] {
        if model.isCreating {
            model.labelsDraft
        } else {
            model.issue?.labels ?? []
        }
    }

    private var tabBadgeCounts: [BodyTab: Int] {
        guard let reviewFindings else { return [:] }
        let count = reviewFindings.openFindings.count
        return count > 0 ? [.diff: count] : [:]
    }

    private var currentKanbanIssue: DiscoveredIssue? {
        guard let folder = model.folderName else { return nil }
        return kanban.issues.first { $0.id == folder }
    }

    private func boardDidChange(_ current: DiscoveredIssue?) {
        model.observeKanban(currentIssue: current)
        seedExistingLabels()
        seedBlockerCandidates()
    }

    private func seedExistingLabels() {
        cachedExistingLabels = kanban.issues.unionedLabels()
            .subtracting(currentLabels)
            .sorted()
    }

    private var currentBlockedBy: [String] {
        if model.isCreating {
            model.blockedByDraft
        } else {
            model.issue?.blockedBy ?? []
        }
    }

    private var resolvedBlockers: [ResolvedBlocker] {
        guard !currentBlockedBy.isEmpty else { return [] }
        return BlockerResolution.resolve(
            blockedBy: currentBlockedBy,
            of: model.folderName ?? "",
            index: BlockerResolution.index(kanban.issues)
        )
    }

    private func seedBlockerCandidates() {
        let selfFolder = model.folderName
        cachedBlockerCandidates = kanban.issues
            .compactMap { discovered -> BlockerCandidate? in
                guard case .valid(let issue) = discovered, issue.folderName != selfFolder else {
                    return nil
                }
                return BlockerCandidate(
                    folderName: issue.folderName, id: issue.id, title: issue.title
                )
            }
            .sorted { $0.id < $1.id }
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
            draftBlocksImplement: issueTypeCatalog.draftBlocksImplement(for: currentType),
            openBlockers: resolvedBlockers.filter { $0.state == .open },
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

    private var detailFieldsDisabled: Bool {
        if model.isCreating {
            false
        } else {
            model.frontmatterError != nil
        }
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

    private func onAddBlocker(_ folderName: String) {
        if model.isCreating {
            if !model.blockedByDraft.contains(folderName) {
                model.blockedByDraft.append(folderName)
            }
            return
        }
        guard let issue = model.issue,
            folderName != issue.folderName,
            !issue.blockedBy.contains(folderName)
        else { return }
        let next = issue.blockedBy + [folderName]
        runFormCommit { try await model.commitBlockedBy(next) }
    }

    private func onRemoveBlocker(_ folderName: String) {
        if model.isCreating {
            model.blockedByDraft.removeAll { $0 == folderName }
            return
        }
        guard let issue = model.issue else { return }
        let next = issue.blockedBy.filter { $0 != folderName }
        runFormCommit { try await model.commitBlockedBy(next) }
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

    private func handleEditorBufferChange() {
        refreshDirtyCache()
        model.scheduleAutoSave()
    }

    private func flushAutoSaveNow() {
        Task { await model.autoSaveNow() }
    }

    // Flush the edited buffer before the selected tab changes away from it.
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
        // The card is the unit of cache: every open spins up a fresh DiffTabModel
        // + GitRepoWatcher so the diff and the live-update signal are scoped to
        // this card's lifetime — deliberately no cross-card diff cache.
        guard diffTabModel == nil else { return }
        let watcher = GitRepoWatcher(repoURL: projectURL)
        let snapshotURL = model.folderName.map {
            IssueLayout.mergedDiffURL(in: projectURL, folderName: $0)
        }
        let diffModel = DiffTabModel(
            repoURL: projectURL,
            baseBranch: model.gitDefaultBranch,
            tipBranch: model.issue?.branch ?? "HEAD",
            snapshotURL: snapshotURL,
            watcher: watcher)
        gitRepoWatcher = watcher
        diffTabModel = diffModel
        diffModel.start()
        if reviewFindings == nil, let folderName = model.folderName {
            reviewFindings = ReviewFindingsModel(
                findingsURL: IssueLayout.reviewFindingsURL(
                    in: projectURL, folderName: folderName)
            )
        }
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
        model.lastMergeCriticalError ?? model.lastMergeError?.localizedDescription
    }

    private func performMerge(
        mode: GitMergeMode, commitSubject: String?, deleteBranch: Bool
    ) async {
        let success = await model.mergeToTarget(
            mode: mode, commitSubject: commitSubject, deleteBranch: deleteBranch)
        guard success, let folderName = model.folderName else { return }
        kanban.signalMergeCompleted(folderName: folderName)
    }

    private var rebaseAndMergeAction: ((GitMergeMode, String?, Bool) -> Void)? {
        guard model.rebaseRecoveryAvailable else { return nil }
        return { mode, commitSubject, deleteBranch in
            Task {
                await performRebaseAndMerge(
                    mode: mode, commitSubject: commitSubject, deleteBranch: deleteBranch)
            }
        }
    }

    private func performRebaseAndMerge(
        mode: GitMergeMode, commitSubject: String?, deleteBranch: Bool
    ) async {
        let success = await model.rebaseAndMergeToTarget(
            mode: mode, commitSubject: commitSubject, deleteBranch: deleteBranch)
        guard success, let folderName = model.folderName else { return }
        kanban.signalMergeCompleted(folderName: folderName)
    }

    private func runFormCommit(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                presentSaveAlert(message: error.localizedDescription)
            }
        }
    }

    private func attemptSave() {
        if model.isCreating {
            guard model.canSaveInCreatingMode else { return }
            createAndNavigate()
            return
        }
        flushAutoSaveNow()
    }

    private func saveAllEditableTabs() async throws {
        // Flush both editable buffers regardless of the selected tab — dirty
        // Spec/Prompt content behind a non-editable tab (PR, Diff) would otherwise
        // be silently dropped. Per-buffer dirty guards keep this cheap when clean.
        var firstError: Error?
        do { try await model.saveBody() } catch { firstError = firstError ?? error }
        do { try await model.savePrompt() } catch { firstError = firstError ?? error }
        if let firstError { throw firstError }
    }

    private func requestChanges() {
        guard let findingsModel = reviewFindings, let folderName = model.folderName else { return }
        Task {
            // Flush dirty buffers first: the task append reads spec.md from disk
            // and a later editor save would clobber the appended tasks.
            do {
                try await saveAllEditableTabs()
            } catch {
                presentSaveAlert(message: error.localizedDescription)
                return
            }
            let taskTexts = findingsModel.openFindings.map(\.reviewFixTaskText)
            guard await model.requestChanges(taskTexts: taskTexts) else { return }
            await findingsModel.markOpenFindingsSent()
            // The launcher owns the busy-checkout handling (worktree vs. queue
            // prompt), so a blocked launch here behaves like any implement start.
            runWorkflow(.implement, folderName, currentType)
        }
    }

    private func triggerWorkflow(_ action: WorkflowAction, folderName: String) {
        // WorkflowCommandResolver reads spec.md and prompt.md from disk, so both
        // dirty buffers must be flushed before the inject. On flush failure,
        // surface and abort — injecting stale content would silently run the workflow outdated.
        Task {
            do {
                try await saveAllEditableTabs()
            } catch {
                presentSaveAlert(message: error.localizedDescription)
                return
            }
            runWorkflow(action, folderName, currentType)
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
        // Everything is already on disk via auto-save; flush the trailing
        // keystrokes and close. A conflict is surfaced by the banner, not here.
        await model.autoSaveNow()
        endAction()
    }

    private func presentSaveAlert(message: String) {
        pendingSaveAlert = SaveAlert(message: message)
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
    .environment(RunStatusModel())
    .frame(width: 900, height: 700)
}
