import CoreServices
import Foundation

// @unchecked Sendable: `stream` is mutated only during init/start/stop, which the
// owning IssueWatcher serializes via its actor-style lifecycle (init then start,
// then a final stop on stream termination). The FSEvents callback only reads
// the immutable `onChange` closure, which is @Sendable. FSEventStreamStop is
// documented to flush in-flight callbacks before returning, so the read-side
// races settle before mutation in stop().
nonisolated final class FSEventSource: @unchecked Sendable {
    private let directory: URL
    private var stream: FSEventStreamRef?
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
        guard stream == nil else { return }
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
        self.stream = newStream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
