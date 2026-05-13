import AppKit
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

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editorFocused: Bool

    init(projectURL: URL, folderName: String) {
        self.projectURL = projectURL
        self.folderName = folderName
        let specURL =
            projectURL
            .appendingPathComponent(".claude")
            .appendingPathComponent("issues")
            .appendingPathComponent(folderName)
            .appendingPathComponent("spec.md")
        _model = State(initialValue: SpecEditorModel(specURL: specURL, folderName: folderName))
    }

    var body: some View {
        VStack(spacing: 0) {
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
                text: bufferBinding,
                position: $editorPosition,
                messages: $editorMessages
            )
            .focused($editorFocused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(folderName)
        .focusedSceneValue(\.specEditorIsActive, true)
        .focusedSceneValue(\.specEditorSave, attemptSave)
        .task(id: model.specURL) {
            do {
                try model.load()
                applyInitialCursor()
                refreshMessages()
            } catch {
                loadFailed = "Failed to load \(folderName): \(error.localizedDescription)"
            }
        }
        .onChange(of: model.frontmatterError) { _, _ in
            refreshMessages()
        }
        .onChange(of: editorFocused) { _, focused in
            if !focused { saveTask() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            saveTask()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) {
            _ in
            saveTask()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveTask() }
        }
        .alert(item: $pendingSaveAlert) { alert in
            Alert(
                title: Text("Failed to save"),
                message: Text(alert.message),
                primaryButton: .default(Text("Try again")) {
                    Task { await attemptPop() }
                },
                secondaryButton: .destructive(Text("Discard changes")) {
                    dismiss()
                }
            )
        }
    }

    private var bufferBinding: Binding<String> {
        Binding(
            get: { model.buffer },
            set: { model.updateBuffer($0) }
        )
    }

    private func refreshMessages() {
        if let error = model.frontmatterError {
            editorMessages = [FrontmatterMessageMap.message(for: error)]
        } else {
            editorMessages = []
        }
    }

    private func applyInitialCursor() {
        if let cursor = model.initialCursor {
            editorPosition = cursor
        }
    }

    private func jumpToError() {
        guard let error = model.frontmatterError else { return }
        let location = FrontmatterMessageMap.location(for: error)
        let offset = TextOffset.offset(ofLine: location.line, column: location.column, in: model.buffer)
        editorPosition.selections = [NSRange(location: offset, length: 0)]
    }

    private func saveTask() {
        Task { try? await model.saveIfDirty() }
    }

    private func attemptSave() {
        Task {
            do {
                try await model.saveIfDirty()
            } catch {
                pendingSaveAlert = SaveAlert(message: error.localizedDescription)
            }
        }
    }

    private func attemptPop() async {
        do {
            try await model.saveIfDirty()
            dismiss()
        } catch {
            pendingSaveAlert = SaveAlert(message: error.localizedDescription)
        }
    }

    private func saveAndRecreate() {
        Task {
            do {
                try await model.resolveConflictSaveAndRecreate()
            } catch {
                pendingSaveAlert = SaveAlert(message: error.localizedDescription)
            }
        }
    }

    private func discardAndPop() {
        dismiss()
    }
}

private struct SaveAlert: Identifiable {
    let id = UUID()
    let message: String
}

extension FocusedValues {
    @Entry var specEditorIsActive: Bool?
    @Entry var specEditorSave: (() -> Void)?
}

#Preview {
    NavigationStack {
        SpecEditorView(
            projectURL: URL(filePath: "/tmp/sample"),
            folderName: "00001-walking-skeleton"
        )
    }
    .frame(width: 800, height: 600)
}
