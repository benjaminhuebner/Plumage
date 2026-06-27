// @preconcurrency: CodeEditorView exposes its default themes as plain
// `static var` (effectively constant). Reading them under Swift 6 strict
// concurrency errors out; the module isn't concurrency-audited.
@preconcurrency import CodeEditorView
import LanguageSupport
import SwiftUI

struct DocEditorView: View {
    let fileURL: URL
    let displayName: String
    // Fired after a successful save (e.g. so a host can refresh a derived view).
    let onSave: (() -> Void)?
    // Fired whenever the dirty state flips, so a host can react to the first edit
    // (e.g. surface a Reset button immediately rather than after a save).
    let onDirtyChange: ((Bool) -> Void)?
    // Fired whenever the auto-save status changes, so a host can show a save indicator.
    let onSaveStatusChange: ((DocEditorModel.AutoSaveStatus) -> Void)?
    // A host-driven counter: each increment asks the editor to discard its in-flight
    // buffer (so the disappear-autosave is a no-op), then calls `onResetComplete`.
    // Lets a "revert" host tear the editor down without its edits being saved back.
    let resetToken: Int
    let onResetComplete: (() -> Void)?

    @State private var model: DocEditorModel
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorMessages: Set<TextLocated<Message>> = []
    @State private var loadFailed: String?
    @State private var saveAlertMessage: String?
    @State private var saveAlertVisible = false
    @State private var probeTask: Task<Void, Never>?
    // Cached focused-scene values. Computing them inline produces a new
    // value (or closure) per body re-eval, which SwiftUI's focus system
    // flags as "FocusedValue update tried to update multiple times per
    // frame" during keystroke bursts.
    @State private var publishedDirtyName: String?
    @State private var publishedDirty: Bool?
    @State private var publishedSaveAction: EditorAction?
    @State private var quitFlushID = UUID()

    private let language: LanguageConfiguration
    private let editorLayout = CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)

    @Environment(\.scenePhase) private var scenePhase
    // CodeEditorView defaults to Theme.defaultLight regardless of system
    // appearance, so the editor stays light in Dark Mode unless we drive the
    // theme off the color scheme ourselves.
    @Environment(\.colorScheme) private var colorScheme

    init(
        fileURL: URL, displayName: String? = nil, fallbackURL: URL? = nil,
        onSave: (() -> Void)? = nil, onDirtyChange: ((Bool) -> Void)? = nil,
        onSaveStatusChange: ((DocEditorModel.AutoSaveStatus) -> Void)? = nil,
        resetToken: Int = 0, onResetComplete: (() -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.displayName = displayName ?? fileURL.lastPathComponent
        self.onSave = onSave
        self.onDirtyChange = onDirtyChange
        self.onSaveStatusChange = onSaveStatusChange
        self.resetToken = resetToken
        self.onResetComplete = onResetComplete
        _model = State(initialValue: DocEditorModel(fileURL: fileURL, fallbackURL: fallbackURL))
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
            .environment(\.codeEditorTheme, colorScheme == .dark ? .defaultDark : .defaultLight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(displayName)
        .focusedSceneValue(\.specEditorIsActive, true)
        .focusedSceneValue(\.specEditorSave, publishedSaveAction)
        // Selection-driven detail has no pop, so the original
        // `\.specEditorClose` pop semantic is meaningless here. Reuse the
        // hook as a manual save-confirm trigger so Cmd-W mid-edit still
        // commits the current buffer before the window closes.
        .focusedSceneValue(\.specEditorClose, publishedSaveAction)
        .focusedSceneValue(\.specEditorDirtyFolderName, publishedDirtyName)
        .task(id: model.fileURL) {
            model.onSaved = { onSave?() }
            if publishedSaveAction == nil {
                publishedSaveAction = EditorAction { Task { await model.autoSaveNow() } }
            }
            // ⌘Q doesn't run .onDisappear reliably; the QuitCoordinator
            // awaits this flush before the app terminates.
            QuitCoordinator.shared.register(quitFlushID) { [weak model] in
                await model?.autoSaveNow()
            }
            loadFailed = nil
            do {
                try await model.load()
            } catch {
                loadFailed = "Failed to load \(displayName): \(error.localizedDescription)"
            }
            refreshDirtyCache()
            model.startPeriodicFlush()
        }
        .onChange(of: model.buffer) { _, _ in
            refreshDirtyCache()
            model.scheduleAutoSave()
        }
        .onChange(of: model.loadedContent) { _, _ in refreshDirtyCache() }
        .onChange(of: model.autoSaveStatus) { _, status in
            onSaveStatusChange?(status)
            if case .error(let message) = status {
                saveAlertMessage = message
                saveAlertVisible = true
            }
        }
        .onChange(of: resetToken) { _, _ in
            // Discard before the host tears us down, so .onDisappear's autosave
            // sees a clean buffer and won't rewrite the file being reset.
            model.discardEdits()
            onResetComplete?()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Cancel any in-flight probe so two quick foreground/background
                // toggles don't race two concurrent disk reads against the
                // same model state.
                probeTask?.cancel()
                probeTask = Task { await model.probeExternalChange() }
            } else {
                Task { await model.autoSaveNow() }
            }
        }
        .onDisappear {
            QuitCoordinator.shared.unregister(quitFlushID)
            model.stopPeriodicFlush()
            // Strong-capture so the trailing flush completes as the view releases its
            // @State; only the debounce is dropped, never the in-flight write.
            Task { [model] in await model.autoSaveNow() }
            probeTask?.cancel()
            model.cancelPendingAutoSave()
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

    private func refreshDirtyCache() {
        let dirty = model.isDirty
        let next = dirty ? displayName : nil
        if publishedDirtyName != next {
            publishedDirtyName = next
        }
        if publishedDirty != dirty {
            publishedDirty = dirty
            onDirtyChange?(dirty)
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
