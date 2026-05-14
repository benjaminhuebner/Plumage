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
    @State private var pendingBodySave: Task<Void, Never>?
    @State private var observeTask: Task<Void, Never>?

    private let markdownLanguage = LanguageConfiguration.markdown()
    // Hides the right-edge minimap so the body editor uses the full width.
    private let editorLayout = CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSpec) private var openSpec
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
        .navigationTitle(navigationTitle)
        .focusedSceneValue(\.specEditorIsActive, true)
        .focusedSceneValue(\.specEditorSave, attemptSave)
        .focusedSceneValue(\.specEditorClose, { Task { await attemptPop() } })
        .focusedSceneValue(\.specEditorDirtyFolderName, dirtyFolderName)
        .task(id: model.specURL) {
            guard !model.isCreating else { return }
            await model.load()
            rawDraft = model.loadedSpecContent
            refreshEditorMessages()
        }
        .onChange(of: model.loadedSpecContent) { _, newContent in
            // Keep raw buffer in sync after silent reloads / form writes.
            // If user is actively editing in raw mode (rawDirty), preserve it.
            if displayMode != .raw || !isRawDirty {
                rawDraft = newContent
            }
        }
        .onChange(of: model.frontmatterError) { _, _ in refreshEditorMessages() }
        .onChange(of: kanban.issues) { _, _ in
            guard let currentFolder = model.folderName else { return }
            let current = kanban.issues.first { $0.id == currentFolder }
            observeTask?.cancel()
            observeTask = Task { await model.observeExternalChange(currentIssue: current) }
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
        }
        .alert(
            "Failed to save",
            isPresented: $saveAlertVisible,
            presenting: pendingSaveAlert
        ) { alert in
            switch alert.kind {
            case .pop:
                Button("Try again") { Task { await attemptPop() } }
                Button("Discard changes", role: .destructive) { dismiss() }
            case .saveOnly:
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
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
                showsRevealInFinder: !model.isCreating,
                saveDisabled: saveDisabled,
                onCopyID: copyID,
                onRevealInFinder: revealInFinder,
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
                get: { synthesizedRawPreview },
                set: { _ in }
            )
        }
        return Binding(
            get: { rawDraft },
            set: { rawDraft = $0 }
        )
    }

    private var synthesizedRawPreview: String {
        let labels = FrontmatterMutator.formatLabels(model.labelsDraft)
        let title =
            model.titleDraft.isEmpty
            ? ""
            : FrontmatterMutator.formatTitleValue(model.titleDraft)
        return """
            ---
            id: <pending>
            title: \(title)
            type: \(model.typeDraft.rawValue)
            status: \(model.statusDraft.rawValue)
            labels: \(labels)
            ---

            \(model.bodyDraft)
            """
    }

    private var saveDisabled: Bool {
        if model.isCreating { return !model.canSaveInCreatingMode }
        return false
    }

    private var detailFieldsDisabled: Bool {
        if model.isCreating { return false }
        return model.frontmatterError != nil
    }

    private var isRawDirty: Bool {
        rawDraft != model.loadedSpecContent
    }

    private var isAnyDirty: Bool {
        switch displayMode {
        case .detail: model.isBodyDirty
        case .raw: isRawDirty
        }
    }

    private var navigationTitle: String {
        if model.isCreating {
            return "New Issue"
        }
        return model.issue?.title ?? model.folderName ?? ""
    }

    private var dirtyFolderName: String? {
        // No folder yet in creating mode → never report a dirty folderName.
        guard !model.isCreating, isAnyDirty else { return nil }
        return model.folderName
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
        editorMessages = []
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
        if model.isCreating {
            guard model.canSaveInCreatingMode else { return }
            let prior = pendingBodySave
            pendingBodySave = Task {
                await prior?.value
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
        let prior = pendingBodySave
        pendingBodySave = Task {
            await prior?.value
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

    private func attemptPop() async {
        // Creating mode never has unsaved disk state: closing leaves no
        // trace and the in-memory drafts go away with the view.
        if model.isCreating {
            dismiss()
            return
        }
        await pendingBodySave?.value
        do {
            switch displayMode {
            case .detail:
                try await model.saveBody()
            case .raw:
                if isRawDirty {
                    try await model.saveRaw(rawDraft)
                }
            }
            dismiss()
        } catch {
            presentSaveAlert(message: error.localizedDescription, kind: .pop)
        }
    }

    private func presentSaveAlert(message: String, kind: SaveAlert.Kind) {
        pendingSaveAlert = SaveAlert(message: message, kind: kind)
        saveAlertVisible = true
    }

    private func copyID() {
        guard let folder = model.folderName else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(folder, forType: .string)
    }

    private func revealInFinder() {
        guard let folder = model.folderName else { return }
        let url = IssueLayout.issueFolder(in: projectURL, folderName: folder)
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
