import CoreServices
import Foundation
import os

// @unchecked Sendable: the `stream` ref is guarded by an OSAllocatedUnfairLock
// instead of an actor so the synchronous IssueWatcher.init + onTermination
// closure call sites stay synchronous. The FSEvents callback only reads the
// immutable `onChange` closure (which is @Sendable). FSEventStreamStop is
// documented to flush in-flight callbacks before returning, so the read-side
// races settle before mutation in stop().
//
// NOTE: unlike SessionLogWatcher, stop()/deinit deliberately do NOT add a
// `queue.sync {}` drain barrier. This source's `onChange` is consumed by the
// IssueWatcher live-sync pipeline, which hops onto the MainActor; a blocking
// `queue.sync` from the MainActor (where stop()/deinit run) deadlocks against
// an in-flight callback that is itself waiting on the MainActor — verified by
// a dispatch_sync deadlock (EXC_BREAKPOINT in __DISPATCH_WAIT_FOR_QUEUE__).
// SessionLogWatcher can drain safely because its callback only enqueues an
// async `Task { @MainActor }` and returns immediately. If the unretained-self
// race ever proves real here, the fix is passRetained + a release callback in
// FSEventStreamContext (CF-style refcounting), not a blocking drain.
nonisolated final class FSEventSource: @unchecked Sendable {
    // FSEventStreamRef is an OpaquePointer (not Sendable) — wrap it so the
    // lock's state type satisfies Sendable. FSEvents stream refs are
    // CFTypeRef-style retain-counted and thread-safe by the framework's
    // contract.
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
            label: "com.plumage.fsevents.\(directory.lastPathComponent)"
        )
    }

    func start() {
        streamLock.withLock { box in
            guard box.ref == nil else { return }
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                let source = Unmanaged<FSEventSource>.fromOpaque(info).takeUnretainedValue()
                source.onChange()
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
        // Safe: deinit only runs once all other refs are dropped, so no
        // concurrent caller can observe the lock during teardown.
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
