import CoreServices
import Foundation
import os

// @unchecked Sendable: `stream` is lock-guarded so init/onTermination stay synchronous.
// stop() must NOT drain via `queue.sync {}` — that deadlocks reproducibly; the dangling-callback
// race is closed by the stream context retaining `self` instead, so every owner MUST call stop().
nonisolated final class FSEventSource: @unchecked Sendable {
    // FSEventStreamRef is an OpaquePointer (not Sendable) — wrap it so the lock's
    // state type satisfies Sendable. FSEvents stream refs are CFTypeRef-style
    // retain-counted and thread-safe by the framework's contract.
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
                retain: { info in
                    guard let info else { return nil }
                    return UnsafeRawPointer(
                        Unmanaged<FSEventSource>.fromOpaque(info).retain().toOpaque())
                },
                release: { info in
                    guard let info else { return }
                    Unmanaged<FSEventSource>.fromOpaque(info).release()
                },
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

    // No deinit teardown: the live stream's context retains self, so deinit
    // is unreachable until stop() has already released the stream.
}
