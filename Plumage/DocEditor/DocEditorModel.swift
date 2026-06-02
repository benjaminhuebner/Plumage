import Foundation

@MainActor
@Observable
final class DocEditorModel {
    enum ConflictState: Equatable {
        case externalChange(diskContent: String)
        case fileDeleted
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

    private nonisolated let writer: DocWriting

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
    // Primary cleanup remains the view's .onDisappear → cancelPendingWork.
    // isolated deinit (Swift 6.2) so we can touch the @MainActor state.
    isolated deinit {
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

    // Called from the view's .onDisappear; see SpecEditorModel.cancelPendingWork.
    func cancelPendingWork() {
        pendingSave?.cancel()
        pendingSave = nil
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
