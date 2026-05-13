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
    @State private var lastSeenIssue: DiscoveredIssue?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectKanbanModel.self) private var kanban
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
                messages: $editorMessages,
                language: .markdown()
            )
            .focused($editorFocused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(folderName)
        .focusedSceneValue(\.specEditorIsActive, true)
        .focusedSceneValue(\.specEditorSave, attemptSave)
        .focusedSceneValue(\.specEditorClose, { Task { await attemptPop() } })
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
        .onChange(of: kanban.issues) { _, _ in
            applyExternalChange()
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
        .alert(
            "Failed to save",
            isPresented: Binding(
                get: { pendingSaveAlert != nil },
                set: { if !$0 { pendingSaveAlert = nil } }
            ),
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

    private func saveTask() {
        Task { try? await model.saveIfDirty() }
    }

    private func attemptSave() {
        Task {
            do {
                try await model.saveIfDirty()
            } catch {
                pendingSaveAlert = SaveAlert(message: error.localizedDescription, kind: .saveOnly)
            }
        }
    }

    private func attemptPop() async {
        do {
            try await model.saveIfDirty()
            dismiss()
        } catch {
            pendingSaveAlert = SaveAlert(message: error.localizedDescription, kind: .pop)
        }
    }

    private func saveAndRecreate() {
        Task {
            do {
                try await model.resolveConflictSaveAndRecreate()
            } catch {
                pendingSaveAlert = SaveAlert(message: error.localizedDescription, kind: .saveOnly)
            }
        }
    }

    private func discardAndPop() {
        dismiss()
    }

    private func applyExternalChange() {
        let current = kanban.issues.first { $0.id == folderName }
        guard let current else {
            lastSeenIssue = nil
            model.handleExternalChange(diskContent: nil)
            return
        }
        if current == lastSeenIssue { return }
        lastSeenIssue = current
        let fresh = try? String(contentsOf: model.specURL, encoding: .utf8)
        if let fresh, fresh == model.loadedContent { return }
        model.handleExternalChange(diskContent: fresh)
    }
}

private struct SaveAlert: Identifiable {
    let id = UUID()
    let message: String
    let kind: Kind

    enum Kind {
        case pop
        case saveOnly
    }
}

extension FocusedValues {
    @Entry var specEditorIsActive: Bool?
    @Entry var specEditorSave: (() -> Void)?
    @Entry var specEditorClose: (() -> Void)?
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
