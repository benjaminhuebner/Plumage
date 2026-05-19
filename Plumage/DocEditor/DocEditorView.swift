import CodeEditorView
import LanguageSupport
import SwiftUI

struct DocEditorView: View {
    let fileURL: URL
    let displayName: String

    @State private var model: DocEditorModel
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorMessages: Set<TextLocated<Message>> = []
    @State private var loadFailed: String?
    @State private var saveAlertMessage: String?
    @State private var saveAlertVisible = false

    private let language: LanguageConfiguration
    private let editorLayout = CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)

    @Environment(\.scenePhase) private var scenePhase

    init(fileURL: URL, displayName: String? = nil) {
        self.fileURL = fileURL
        self.displayName = displayName ?? fileURL.lastPathComponent
        _model = State(initialValue: DocEditorModel(fileURL: fileURL))
        self.language = DocEditorLanguage.configuration(for: fileURL)
    }

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            DocEditorBanner(
                conflict: model.conflict,
                onReload: { model.resolveConflictReload() },
                onKeep: { model.resolveConflictKeep() },
                onSaveAndRecreate: saveAndRecreate
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
                language: language
            )
            .environment(\.codeEditorLayoutConfiguration, editorLayout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(displayName)
        .focusedSceneValue(\.specEditorIsActive, true)
        .focusedSceneValue(\.specEditorSave, attemptSave)
        // Selection-driven detail has no pop, so the original
        // `\.specEditorClose` pop semantic is meaningless here. Reuse the
        // hook as a manual save-confirm trigger so Cmd-W mid-edit still
        // commits the current buffer before the window closes.
        .focusedSceneValue(\.specEditorClose, attemptSave)
        .focusedSceneValue(\.specEditorDirtyFolderName, model.isDirty ? displayName : nil)
        .task(id: model.fileURL) {
            loadFailed = nil
            do {
                try await model.load()
            } catch {
                loadFailed = "Failed to load \(displayName): \(error.localizedDescription)"
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.probeExternalChange() }
            } else {
                attemptSave()
            }
        }
        .onDisappear {
            // attemptSave is fire-and-forget; cancelPendingWork ensures any
            // earlier queued saves are cancelled rather than landing post-pop.
            // The latest save still runs because attemptSave queues a new
            // task after the cancel (the model's saveGeneration check
            // prevents the cancelled one from clobbering state on return).
            attemptSave()
            model.cancelPendingWork()
        }
        .alert(
            "Failed to save",
            isPresented: $saveAlertVisible,
            presenting: saveAlertMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func attemptSave() {
        Task {
            do {
                try await model.saveIfDirty()
            } catch {
                saveAlertMessage = error.localizedDescription
                saveAlertVisible = true
            }
        }
    }

    private func saveAndRecreate() {
        Task {
            do {
                try await model.resolveConflictSaveAndRecreate()
            } catch {
                saveAlertMessage = error.localizedDescription
                saveAlertVisible = true
            }
        }
    }
}

private struct DocEditorBanner: View {
    let conflict: DocEditorModel.ConflictState?
    let onReload: () -> Void
    let onKeep: () -> Void
    let onSaveAndRecreate: () -> Void

    var body: some View {
        if let conflict {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message(for: conflict))
                    .font(.callout)
                Spacer()
                switch conflict {
                case .externalChange:
                    Button("Use disk", action: onReload)
                    Button("Keep mine", action: onKeep)
                case .fileDeleted:
                    Button("Save and recreate", action: onSaveAndRecreate)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12))
        }
    }

    private func message(for conflict: DocEditorModel.ConflictState) -> String {
        switch conflict {
        case .externalChange:
            return "The file changed on disk while you were editing."
        case .fileDeleted:
            return "The file no longer exists on disk."
        }
    }
}

#Preview {
    DocEditorView(
        fileURL: URL(filePath: "/tmp/sample/.claude/docs/PROJECT.md")
    )
    .frame(width: 800, height: 600)
}
