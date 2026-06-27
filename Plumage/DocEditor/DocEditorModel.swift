import Foundation
import os

@MainActor
@Observable
final class DocEditorModel {
    enum ConflictState: Equatable {
        case externalChange(diskContent: String)
        case fileDeleted
    }

    enum AutoSaveStatus: Equatable, Sendable {
        case idle
        case saving
        case saved
        case error(message: String)
    }

    let fileURL: URL
    // Saves always target `fileURL`, but while it is absent the buffer seeds from
    // here and the file is still reported not-on-disk — so a host can open an
    // overridable asset without an override being written until a real edit lands.
    let fallbackURL: URL?

    var buffer: String = ""
    private(set) var loadedContent: String = ""
    private(set) var conflict: ConflictState?
    private(set) var lastWrittenContent: String?
    private(set) var fileExistsOnDisk: Bool = false
    private(set) var autoSaveStatus: AutoSaveStatus = .idle

    // Fires after a successful write so a host can refresh a derived view.
    var onSaved: @MainActor () -> Void = {}

    private nonisolated let writer: DocWriting
    private static let logger = Logger(subsystem: "com.plumage", category: "DocEditorModel")

    // Mirrors ProjectSettingsModel/IssueDetailModel: write debounced against typing spam.
    static let autoSaveDebounce: Duration = .milliseconds(500)
    // Crash net: the debounce never fires under uninterrupted typing, so a hard kill could
    // still lose the whole burst — this bounds that loss to one interval.
    static let periodicFlushInterval: Duration = .seconds(5)

    // The debounce timer; separate from the write task so teardown can drop a pending
    // debounce without cancelling an in-flight write.
    private var pendingAutoSave: Task<Void, Never>?
    private var periodicFlushTask: Task<Void, Never>?
    // Serializes overlapping save triggers (focus loss + ⌘S + scenePhase).
    private var pendingSave: Task<Void, Error>?
    // Bumped on save start and resolveConflictReload; a mid-flight reload
    // invalidates the still-running save so its post-write state-mutation
    // is dropped. Wrapping increment: overflow at 2^64 saves is unreachable
    // in practice, but `&+=` avoids the debug-mode trap.
    private var saveGeneration: UInt64 = 0

    var isDirty: Bool { buffer != loadedContent }

    init(fileURL: URL, fallbackURL: URL? = nil, writer: DocWriting = DefaultDocWriter()) {
        self.fileURL = fileURL
        self.fallbackURL = fallbackURL
        self.writer = writer
    }

    // Safety net for abnormal teardown paths where .onDisappear is skipped.
    // isolated deinit (Swift 6.2) so we can touch the @MainActor state.
    isolated deinit {
        pendingAutoSave?.cancel()
        periodicFlushTask?.cancel()
        pendingSave?.cancel()
    }

    func load() async throws {
        let url = fileURL
        let fallback = fallbackURL
        let result = await Task.detached(priority: .userInitiated) { () -> (String, Bool) in
            if let data = try? String(contentsOf: url, encoding: .utf8) {
                return (data, true)
            }
            // No file at the primary URL yet: seed from the read-only baseline if
            // one is set, but report it as not-on-disk so saves create it fresh.
            if let fallback, let data = try? String(contentsOf: fallback, encoding: .utf8) {
                return (data, false)
            }
            return ("", false)
        }.value
        let raw = result.0
        fileExistsOnDisk = result.1
        let content = raw.replacingOccurrences(of: "\r\n", with: "\n")
        loadedContent = content
        buffer = content
        conflict = nil
    }

    func saveIfDirty() async throws {
        guard isDirty else { return }
        let snapshot = buffer
        let prior = pendingSave
        saveGeneration &+= 1
        let myGeneration = saveGeneration
        let task = Task<Void, Error> { [weak self] in
            _ = try? await prior?.value
            guard let self else { return }
            try await self.writeOffActor(snapshot)
            guard self.saveGeneration == myGeneration else { return }
            self.lastWrittenContent = snapshot
            self.loadedContent = snapshot
            self.fileExistsOnDisk = true
        }
        pendingSave = task
        try await task.value
    }

    // Debounced save-on-edit: the view calls this on every buffer change so an
    // edit reaches disk within the debounce window even without a close or quit.
    func scheduleAutoSave() {
        pendingAutoSave?.cancel()
        autoSaveStatus = .idle
        pendingAutoSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.autoSaveDebounce)
            guard !Task.isCancelled else { return }
            await self?.performAutoSave()
        }
    }

    // Flush a pending debounce and write now. Used by close/background/⌘Q/⌘S so a
    // sub-debounce edit still lands.
    func autoSaveNow() async {
        pendingAutoSave?.cancel()
        pendingAutoSave = nil
        await performAutoSave()
    }

    // Force a write every interval regardless of the debounce, so a hard kill during a
    // long uninterrupted edit loses at most one interval. Started on mount, stopped on teardown.
    func startPeriodicFlush(every interval: Duration? = nil) {
        let interval = interval ?? Self.periodicFlushInterval
        periodicFlushTask?.cancel()
        periodicFlushTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.performAutoSave()
            }
        }
    }

    func stopPeriodicFlush() {
        periodicFlushTask?.cancel()
        periodicFlushTask = nil
    }

    private func performAutoSave() async {
        // A blind write under an unresolved external conflict would clobber the disk copy.
        if case .externalChange = conflict { return }
        guard isDirty else { return }
        autoSaveStatus = .saving
        do {
            try await saveIfDirty()
            autoSaveStatus = .saved
            onSaved()
        } catch {
            // Teardown writes after any banner is gone, so log too, not only the status.
            Self.logger.warning("auto-save failed: \(error.localizedDescription, privacy: .public)")
            autoSaveStatus = .error(message: error.localizedDescription)
        }
    }

    // Cancel only the debounce timer — never an in-flight write. Safe from .onDisappear.
    func cancelPendingAutoSave() {
        pendingAutoSave?.cancel()
        pendingAutoSave = nil
    }

    // Drop the in-flight buffer back to the loaded content and cancel both the debounce
    // and any in-flight write, so a reset truly discards unsaved edits (reset-before-save).
    func discardEdits() {
        cancelPendingAutoSave()
        pendingSave?.cancel()
        pendingSave = nil
        buffer = loadedContent
    }

    func probeExternalChange() async {
        let url = fileURL
        let result = await Task.detached(priority: .utility) { () -> (String?, Bool) in
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                return (raw, true)
            }
            return (nil, false)
        }.value
        let diskContent = result.0
        let existsOnDisk = result.1
        // A file that never existed yet (user-created-on-save scenario) is
        // not a conflict — the buffer is the source of truth until the
        // first save lands.
        if !existsOnDisk && !fileExistsOnDisk { return }
        if let raw = diskContent {
            let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
            if normalized == loadedContent || normalized == lastWrittenContent { return }
            handleExternalChange(diskContent: normalized)
        } else {
            handleExternalChange(diskContent: nil)
        }
    }

    func handleExternalChange(diskContent: String?) {
        guard let diskContent else {
            // Treat disappearance as fileDeleted only if we previously saw
            // the file on disk — otherwise an unsaved scratch edit
            // shouldn't surface a banner.
            if fileExistsOnDisk {
                conflict = .fileDeleted
            }
            return
        }
        if !isDirty {
            loadedContent = diskContent
            buffer = diskContent
            conflict = nil
        } else if diskContent != loadedContent {
            conflict = .externalChange(diskContent: diskContent)
        }
    }

    func resolveConflictReload() {
        guard case .externalChange(let diskContent) = conflict else { return }
        cancelPendingAutoSave()
        saveGeneration &+= 1
        loadedContent = diskContent
        buffer = diskContent
        conflict = nil
    }

    func resolveConflictKeep() {
        conflict = nil
    }

    func resolveConflictSaveAndRecreate() async throws {
        let snapshot = buffer
        let prior = pendingSave
        saveGeneration &+= 1
        let myGeneration = saveGeneration
        let task = Task<Void, Error> { [weak self] in
            _ = try? await prior?.value
            guard let self else { return }
            try await self.writeOffActor(snapshot)
            guard self.saveGeneration == myGeneration else { return }
            self.lastWrittenContent = snapshot
            self.loadedContent = snapshot
            self.fileExistsOnDisk = true
            self.conflict = nil
        }
        pendingSave = task
        try await task.value
    }

    private func writeOffActor(_ content: String) async throws {
        let url = fileURL
        let writer = self.writer
        try await Task.detached(priority: .utility) {
            try writer.write(content, to: url)
        }.value
    }
}

nonisolated protocol DocWriting: Sendable {
    func write(_ content: String, to url: URL) throws
}

nonisolated struct DefaultDocWriter: DocWriting {
    func write(_ content: String, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
