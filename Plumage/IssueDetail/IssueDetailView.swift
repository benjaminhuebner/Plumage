import AppKit
import CodeEditorView
import LanguageSupport
import SwiftUI

struct IssueDetailView: View {
    let projectURL: URL

    @State private var model: IssueDetailModel
    @State private var rawDraft: String = ""
    @State private var displayMode: DisplayMode = .detail
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorMessages: Set<TextLocated<Message>> = []
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
    @Environment(ProjectKanbanModel.self) private var kanban

    enum DisplayMode: String, CaseIterable, Identifiable {
        case detail = "Detail"
        case raw = "Raw"
        var id: String { rawValue }
    }

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
            rawDraft = model.loadedSpecContent
            refreshEditorMessages()
            refreshDirtyCache()
        }
        .onChange(of: dismissToOrigin == nil) { _, _ in refreshBackToBoardCache() }
        .onChange(of: model.loadedSpecContent) { _, newContent in
            // Keep raw buffer in sync after silent reloads / form writes.
            // If user is actively editing in raw mode (rawDirty), preserve it.
            if displayMode != .raw || !isRawDirty {
                rawDraft = newContent
            }
            refreshDirtyCache()
        }
        .onChange(of: model.loadedBodyContent) { _, _ in refreshDirtyCache() }
        .onChange(of: model.bodyDraft) { _, _ in refreshDirtyCache() }
        .onChange(of: rawDraft) { _, _ in refreshDirtyCache() }
        .onChange(of: model.frontmatterError) { _, _ in refreshEditorMessages() }
        .onChange(of: currentKanbanIssue) { _, current in
            model.observeKanban(currentIssue: current)
        }
        .onChange(of: kanban.lastRemovalCompleted) { _, completed in
            if let completed, completed == model.folderName { dismiss() }
        }
        .onChange(of: model.conflict) { _, conflict in
            if conflict == .fileDeleted { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Auto-save on background only applies in loaded mode. In creating
            // mode there is no disk state yet — Cmd-W / back-nav dismisses
            // without persisting (per spec: keine Disk-Spur).
            if phase != .active && !model.isCreating { attemptSave() }
        }
        .onChange(of: displayMode) { _, newMode in
            // Switching INTO raw should snapshot the current disk content as
            // the buffer's baseline, so the user starts from a clean view.
            // In creating mode the raw view shows a synthesized preview,
            // computed on the fly via `synthesizedRawPreview`; no snapshot.
            if newMode == .raw && !model.isCreating {
                rawDraft = model.loadedSpecContent
            }
            refreshEditorMessages()
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
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if !model.isCreating {
                IssueDetailBanner(
                    frontmatterError: model.frontmatterError,
                    conflict: model.conflict,
                    onReload: {
                        model.resolveConflictReload()
                        rawDraft = model.loadedSpecContent
                    },
                    onKeep: { model.resolveConflictKeep() }
                )
            }
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
    }

    // Single render path for both creating and loaded modes. The mode-specific
    // bits flow through the `current*`/`on*` helpers below so this layout
    // (TopBar → Hero → FormRows → Body editor, or TopBar → Raw editor) stays
    // identical regardless of whether the issue is on disk yet.
    @ViewBuilder
    private func renderedDetail() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            IssueDetailTopBar(
                paddedID: paddedID,
                branch: branch,
                displayMode: $displayMode,
                showsDisplayModeToggle: true,
                showsCopyID: !model.isCreating,
                saveDisabled: saveDisabled,
                onCopyID: model.copyIDToPasteboard,
                onSave: attemptSave
            )
            switch displayMode {
            case .detail:
                detailBody
            case .raw:
                rawBody
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var detailBody: some View {
        IssueDetailHero(
            status: currentStatus,
            type: currentType,
            labels: currentLabels,
            titleDraft: titleBinding,
            titlePlaceholder: model.isCreating ? "Issue title" : "Title",
            autoFocusTitle: model.isCreating,
            onCommitTitle: onCommitTitle,
            onAddLabel: onAddLabel,
            onRemoveLabel: onRemoveLabel,
            isDisabled: detailFieldsDisabled
        )
        Divider()
        IssueDetailFormRows(
            type: currentType,
            status: currentStatus,
            dates: formDates,
            onSelectType: onSelectType,
            onSelectStatus: onSelectStatus,
            isDisabled: detailFieldsDisabled
        )
        Divider()
        CodeEditor(
            text: bodyBinding,
            position: $editorPosition,
            messages: $editorMessages,
            language: markdownLanguage
        )
        .environment(\.codeEditorLayoutConfiguration, editorLayout)
        .frame(minHeight: 240)
    }

    @ViewBuilder
    private var rawBody: some View {
        CodeEditor(
            text: rawBinding,
            position: $editorPosition,
            messages: $editorMessages,
            language: markdownLanguage
        )
        .environment(\.codeEditorLayoutConfiguration, editorLayout)
        .frame(minHeight: 240)
        // Creating mode has no on-disk spec yet: the raw view shows a live
        // preview of what would be written on save, but isn't editable.
        .disabled(model.isCreating)
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

    private var formDates: IssueDetailFormRows.Dates? {
        guard !model.isCreating, let issue = model.issue else { return nil }
        return .init(created: issue.created, updated: issue.updated)
    }

    private var paddedID: String? {
        guard !model.isCreating, let issue = model.issue else { return nil }
        return "#" + IssueIDFormatter.padded(issue.id, width: 5)
    }

    private var branch: String? {
        guard !model.isCreating, let issue = model.issue else { return nil }
        return issue.branch
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { model.titleDraft },
            set: { model.titleDraft = $0 }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { model.bodyDraft },
            set: { model.bodyDraft = $0 }
        )
    }

    private var rawBinding: Binding<String> {
        if model.isCreating {
            // Read-only synthesized preview; the setter is a no-op because
            // the editor is .disabled() in creating mode.
            return Binding(
                get: { model.synthesizedRawPreview },
                set: { _ in }
            )
        }
        return Binding(
            get: { rawDraft },
            set: { rawDraft = $0 }
        )
    }

    private var saveDisabled: Bool {
        if model.isCreating { return !model.canSaveInCreatingMode }
        return false
    }

    private var detailFieldsDisabled: Bool {
        if model.isCreating { return false }
        return model.frontmatterError != nil
    }

    // Local thin wrapper — the model owns the dirty check, but it needs to
    // be passed `rawDraft` because the raw buffer still lives on the view
    // (sync with model.loadedSpecContent via onChange handlers).
    private var isRawDirty: Bool {
        model.isRawDirty(rawDraft)
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
        // Markers point into the raw spec (line/column relative to frontmatter),
        // so the detail-mode body editor would render them at meaningless rows.
        guard displayMode == .raw, let error = model.frontmatterError else {
            if !editorMessages.isEmpty { editorMessages = [] }
            return
        }
        let next: Set<TextLocated<Message>> = [FrontmatterMessageMap.message(for: error)]
        if editorMessages != next { editorMessages = next }
    }

    private func refreshDirtyCache() {
        let next = model.dirtyFolderName(rawDirty: isRawDirty)
        if publishedDirtyFolderName != next {
            publishedDirtyFolderName = next
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
        // Fire-and-forget: IssueDetailModel serializes overlapping
        // saveBody/saveRaw calls on its own pendingBodySave chain, so a
        // rapid double-click of Save just queues a no-op (guard-by-dirty)
        // after the in-flight write finishes.
        if model.isCreating {
            guard model.canSaveInCreatingMode else { return }
            Task {
                do {
                    try await model.createIssueFromDraft()
                } catch IssueDetailModel.SaveError.emptyTitle {
                    // Save was gated by canSaveInCreatingMode; no alert needed.
                } catch {
                    presentSaveAlert(message: error.localizedDescription, kind: .saveOnly)
                }
            }
            return
        }
        Task {
            do {
                switch displayMode {
                case .detail:
                    try await model.saveBody()
                case .raw:
                    try await model.saveRaw(rawDraft)
                }
            } catch {
                presentSaveAlert(message: error.localizedDescription, kind: .saveOnly)
            }
        }
    }

    private func triggerPop() {
        Task { await attemptPop(endAction: { dismiss() }) }
    }

    private func triggerBack(_ action: @escaping () -> Void) {
        Task { await attemptPop(endAction: action) }
    }

    private var backToBoardAction: (() -> Void)? {
        dismissToOrigin.map { action in { triggerBack(action) } }
    }

    private func attemptPop(endAction: @escaping () -> Void) async {
        // Creating mode never has unsaved disk state: closing leaves no
        // trace and the in-memory drafts go away with the view.
        if model.isCreating {
            endAction()
            return
        }
        do {
            switch displayMode {
            case .detail:
                try await model.saveBody()
            case .raw:
                if isRawDirty {
                    try await model.saveRaw(rawDraft)
                }
            }
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
