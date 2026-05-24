import CoreServices
import Foundation
import os

// @unchecked Sendable: mirrors IssueCore/FSEventSource — the `stream` ref is
// guarded by an OSAllocatedUnfairLock instead of an actor so the synchronous
// TerminalClaudeSession.markStarted/stop call sites stay synchronous. The
// FSEvents callback only reads the immutable `onChange` closure (which is
// @Sendable). FSEventStreamStop flushes in-flight callbacks before returning,
// so read-side races settle before mutation in stop(). Kept as a separate
// type from FSEventSource (not extracted to a shared utility): two callers
// is below the "rule of three" extraction trigger — see decisions.md.
nonisolated final class SessionLogWatcher: @unchecked Sendable {
    private struct StreamBox: @unchecked Sendable {
        var ref: FSEventStreamRef?
    }

    private let directory: URL
    private let streamLock = OSAllocatedUnfairLock<StreamBox>(initialState: StreamBox(ref: nil))
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void

    init(directory: URL, onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.onChange = onChange
        self.queue = DispatchQueue(
            label: "com.plumage.sessionlog.\(directory.lastPathComponent)"
        )
    }

    func start() {
        streamLock.withLock { box in
            guard box.ref == nil else { return }
            // FSEvents accepts a non-existing path (the stream simply never
            // fires until something materialises), but creating the directory
            // up-front lets us catch the very first `<id>.jsonl` write that
            // claude performs during boot — without it, the rotated post-/clear
            // session would only be observed on the second event.
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<SessionLogWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.onChange()
            }
            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )
            guard
                let newStream = FSEventStreamCreate(
                    kCFAllocatorDefault,
                    callback,
                    &context,
                    [directory.path as CFString] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    0.05,
                    flags
                )
            else { return }
            FSEventStreamSetDispatchQueue(newStream, queue)
            FSEventStreamStart(newStream)
            box.ref = newStream
        }
    }

    func stop() {
        streamLock.withLock { box in
            guard let current = box.ref else { return }
            FSEventStreamStop(current)
            FSEventStreamInvalidate(current)
            FSEventStreamRelease(current)
            box.ref = nil
        }
    }

    deinit {
        streamLock.withLock { box in
            if let current = box.ref {
                FSEventStreamStop(current)
                FSEventStreamInvalidate(current)
                FSEventStreamRelease(current)
                box.ref = nil
            }
        }
    }
}
