import CodeEditorView
import LanguageSupport
import SwiftUI

struct SpecEditorView: View {
    let projectURL: URL
    let folderName: String

    @State private var model: SpecEditorModel
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorMessages: Set<TextLocated<Message>> = []
    @State private var loadFailed: String?
    @State private var pendingSaveAlert: SaveAlert?
    @State private var saveAlertVisible: Bool = false
    @State private var observeTask: Task<Void, Never>?

    private let markdownLanguage = LanguageConfiguration.markdown()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectKanbanModel.self) private var kanban
    @FocusState private var editorFocused: Bool

    init(projectURL: URL, folderName: String) {
        self.projectURL = projectURL
        self.folderName = folderName
        let specURL = IssueLayout.specURL(in: projectURL, folderName: folderName)
        _model = State(initialValue: SpecEditorModel(specURL: specURL, folderName: folderName))
    }

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            SpecEditorBanner(
                frontmatterError: model.frontmatterError,
                conflict: model.conflict,
                onJumpToError: jumpToError,
                onReload: { model.resolveConflictReload() },
                onKeep: { model.resolveConflictKeep() },
                onSaveAndRecreate: saveAndRecreate,
                onDiscard: discardAndPop
            )
            if let loadFailed {
                Text(loadFailed)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            CodeEditor(
                text: $model.buffer,
                position: $editorPosition,
                messages: $editorMessages,
                language: markdownLanguage
            )
            .focused($editorFocused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(folderName)
        .focusedSceneValue(\.specEditorIsActive, true)
        .focusedSceneValue(\.specEditorSave, attemptSave)
        .focusedSceneValue(\.specEditorClose, { Task { await attemptPop() } })
        .focusedSceneValue(
            \.specEditorDirtyFolderName,
            model.isDirty ? model.folderName : nil
        )
        .task(id: model.specURL) {
            loadFailed = nil
            do {
                try await model.load()
                applyInitialCursor()
                refreshMessages()
            } catch {
                loadFailed = "Failed to load \(folderName): \(error.localizedDescription)"
            }
        }
        .onChange(of: model.frontmatterError) { _, _ in
            refreshMessages()
        }
        .onChange(of: kanban.issues) { _, _ in
            let current = kanban.issues.first { $0.id == folderName }
            observeTask?.cancel()
            observeTask = Task { await model.observeExternalChange(currentIssue: current) }
        }
        .onChange(of: editorFocused) { _, focused in
            if !focused { saveTask() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveTask() }
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

    private func refreshMessages() {
        if let error = model.frontmatterError {
            editorMessages = [FrontmatterMessageMap.message(for: error)]
        } else {
            editorMessages = []
        }
    }

    private func applyInitialCursor() {
        if let offset = model.initialCursorOffset {
            editorPosition = CodeEditor.Position(
                selections: [NSRange(location: offset, length: 0)],
                verticalScrollPosition: 0
            )
        }
    }

    private func jumpToError() {
        guard let error = model.frontmatterError else { return }
        let location = FrontmatterMessageMap.location(for: error)
        let offset = TextOffset.offset(ofLine: location.line, column: location.column, in: model.buffer)
        editorPosition.selections = [NSRange(location: offset, length: 0)]
    }

    private func presentSaveAlert(message: String, kind: SaveAlert.Kind) {
        pendingSaveAlert = SaveAlert(message: message, kind: kind)
        saveAlertVisible = true
    }

    private func saveTask() {
        Task {
            do {
                try await model.saveIfDirty()
            } catch {
                presentSaveAlert(message: error.localizedDescription, kind: .saveOnly)
            }
        }
    }

    private func attemptSave() {
        Task {
            do {
                try await model.saveIfDirty()
            } catch {
                presentSaveAlert(message: error.localizedDescription, kind: .saveOnly)
            }
        }
    }

    private func attemptPop() async {
        do {
            try await model.saveIfDirty()
            dismiss()
        } catch {
            presentSaveAlert(message: error.localizedDescription, kind: .pop)
        }
    }

    private func saveAndRecreate() {
        Task {
            do {
                try await model.resolveConflictSaveAndRecreate()
            } catch {
                presentSaveAlert(message: error.localizedDescription, kind: .saveOnly)
            }
        }
    }

    private func discardAndPop() {
        dismiss()
    }
}

extension FocusedValues {
    @Entry var specEditorIsActive: Bool?
    @Entry var specEditorSave: (() -> Void)?
    @Entry var specEditorClose: (() -> Void)?
    @Entry var specEditorDirtyFolderName: String?
}

#Preview {
    NavigationStack {
        SpecEditorView(
            projectURL: URL(filePath: "/tmp/sample"),
            folderName: "00001-walking-skeleton"
        )
    }
    .environment(ProjectKanbanModel())
    .frame(width: 800, height: 600)
}
