import AppKit
import CodeEditorView
import LanguageSupport
import SwiftUI

struct IssueDetailView: View {
    let projectURL: URL
    let folderName: String

    @State private var model: IssueDetailModel
    @State private var titleDraft: String = ""
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
        self.folderName = folderName
        let specURL = IssueLayout.specURL(in: projectURL, folderName: folderName)
        _model = State(initialValue: IssueDetailModel(specURL: specURL, folderName: folderName))
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
        .navigationTitle(model.issue?.title ?? folderName)
        .focusedSceneValue(\.specEditorIsActive, true)
        .focusedSceneValue(\.specEditorSave, attemptSave)
        .focusedSceneValue(\.specEditorClose, { Task { await attemptPop() } })
        .focusedSceneValue(\.specEditorDirtyFolderName, isAnyDirty ? folderName : nil)
        .task(id: model.specURL) {
            await model.load()
            if let issue = model.issue {
                titleDraft = issue.title
            }
            rawDraft = model.loadedSpecContent
            refreshEditorMessages()
        }
        .onChange(of: model.issue?.title) { _, newTitle in
            if let newTitle, newTitle != titleDraft {
                titleDraft = newTitle
            }
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
            let current = kanban.issues.first { $0.id == folderName }
            observeTask?.cancel()
            observeTask = Task { await model.observeExternalChange(currentIssue: current) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { attemptSave() }
        }
        .onChange(of: displayMode) { _, newMode in
            // Switching INTO raw should snapshot the current disk content as
            // the buffer's baseline, so the user starts from a clean view.
            if newMode == .raw {
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
            IssueDetailBanner(
                frontmatterError: model.frontmatterError,
                conflict: model.conflict,
                onReload: {
                    model.resolveConflictReload()
                    rawDraft = model.loadedSpecContent
                },
                onKeep: { model.resolveConflictKeep() }
            )
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
                if let issue = model.issue {
                    loadedContent(issue: issue)
                } else {
                    Text("Issue could not be parsed.")
                        .foregroundStyle(.secondary)
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func loadedContent(issue: Issue) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            IssueDetailTopBar(
                paddedID: "#" + IssueIDFormatter.padded(issue.id, width: 5),
                branch: issue.branch,
                displayMode: $displayMode,
                onCopyID: copyID,
                onRevealInFinder: revealInFinder,
                onSave: attemptSave
            )
            switch displayMode {
            case .detail:
                detailBody(issue: issue)
            case .raw:
                rawBody
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func detailBody(issue: Issue) -> some View {
        IssueDetailHero(
            issue: issue,
            titleDraft: $titleDraft,
            onCommitTitle: commitTitle,
            onAddLabel: { newLabel in
                let next = issue.labels + [newLabel]
                runFormCommit { try await model.commitLabels(next) }
            },
            onRemoveLabel: { label in
                let next = issue.labels.filter { $0 != label }
                runFormCommit { try await model.commitLabels(next) }
            },
            isDisabled: model.frontmatterError != nil
        )
        Divider()
        IssueDetailFormRows(
            issue: issue,
            onSelectType: { newType in runFormCommit { try await model.commitType(newType) } },
            onSelectStatus: { newStatus in
                runFormCommit { try await model.commitStatus(newStatus) }
            },
            isDisabled: model.frontmatterError != nil
        )
        Divider()
        CodeEditor(
            text: $model.bodyDraft,
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
            text: $rawDraft,
            position: $editorPosition,
            messages: $editorMessages,
            language: markdownLanguage
        )
        .environment(\.codeEditorLayoutConfiguration, editorLayout)
        .frame(minHeight: 240)
    }

    private var backgroundTint: some View {
        let color = model.issue?.type.color ?? .gray
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

    private var isRawDirty: Bool {
        rawDraft != model.loadedSpecContent
    }

    private var isAnyDirty: Bool {
        switch displayMode {
        case .detail: model.isBodyDirty
        case .raw: isRawDirty
        }
    }

    private func refreshEditorMessages() {
        editorMessages = []
    }

    private func commitTitle() {
        runFormCommit { try await model.commitTitle(titleDraft) }
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(folderName, forType: .string)
    }

    private func revealInFinder() {
        let url = IssueLayout.issueFolder(in: projectURL, folderName: folderName)
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
