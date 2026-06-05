import CoreServices
import Foundation
import os

// @unchecked Sendable: mirrors IssueCore/FSEventSource — the `stream` ref is
// guarded by an OSAllocatedUnfairLock instead of an actor so the synchronous
// TerminalClaudeSession.markStarted/stop call sites stay synchronous. The
// FSEvents callback only reads the immutable `onChange` closure (which is
// @Sendable). stop()/deinit run a queue.sync barrier on the (serial) FSEvents
// delivery queue before tearing down the stream — this drains any callback
// already dispatched but mid-flight, so the Unmanaged.passUnretained pointer
// inside FSEventStreamContext never becomes dangling. FSEventStreamStop alone
// does NOT guarantee a synchronous drain when invoked cross-queue (Apple's
// docs only spec the flush on same-queue calls), so the barrier is load-
// bearing — do not remove. Kept as a separate type from FSEventSource (not
// extracted to a shared utility): two callers is below the "rule of three"
// extraction trigger — see decisions.md.
nonisolated final class SessionLogWatcher: @unchecked Sendable {
    private struct StreamBox: @unchecked Sendable {
        var ref: FSEventStreamRef?
    }

    private let directory: URL
    private let streamLock = OSAllocatedUnfairLock<StreamBox>(initialState: StreamBox(ref: nil))
    // Serial is load-bearing: queue.sync {} below relies on FIFO ordering to
    // act as a drain barrier. Switching to a concurrent queue would break the
    // drain guarantee and reopen the dangling-pointer race in deinit.
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void

    init(directory: URL, onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.onChange = onChange
        // Full path, not lastPathComponent: two projects with the same folder
        // name would otherwise share a queue label, which muddies lldb /
        // Instruments inspection.
        self.queue = DispatchQueue(
            label: "com.plumage.sessionlog.\(directory.path)"
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
        // Drain any callback that's already been dispatched onto the serial
        // queue but hasn't started executing yet. Without this barrier a
        // mid-flight callback could call into self via the unretained pointer
        // after streamLock releases the stream. Safe from MainActor: callback
        // body only dispatches a fresh Task @MainActor and returns immediately,
        // so the sync wait is bounded.
        queue.sync {}
        streamLock.withLock { box in
            guard let current = box.ref else { return }
            FSEventStreamStop(current)
            FSEventStreamInvalidate(current)
            FSEventStreamRelease(current)
            box.ref = nil
        }
    }

    deinit {
        // ARC guarantees no other strong refs at this point, so no other
        // thread is calling start()/stop() concurrently. Drain the queue the
        // same way stop() does to close the race against an already-dispatched
        // FSEvents callback.
        queue.sync {}
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
