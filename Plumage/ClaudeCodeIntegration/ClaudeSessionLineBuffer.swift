import Foundation

extension ClaudeSession {
    // @unchecked Sendable: NSLock serializes every access to `partial` (mutated from
    // readabilityHandler's queue and onTermination). Splits raw bytes on 0x0A before
    // decoding — whole-chunk decode drops data when UTF-8 spans a chunk boundary.
    nonisolated final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var partial = Data()

        func append(_ data: Data) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            partial.append(data)
            var lines: [String] = []
            // Most stdout chunks carry zero or one newline; preallocate
            // for the common case so a streaming burst doesn't trip the
            // array's growth doubling on every chunk.
            lines.reserveCapacity(4)
            while let nl = partial.firstIndex(of: 0x0A) {
                lines.append(
                    String(decoding: partial[partial.startIndex..<nl], as: UTF8.self))
                partial.removeSubrange(partial.startIndex...nl)
            }
            return lines
        }

        func flush() -> String? {
            lock.lock()
            defer { lock.unlock() }
            guard !partial.isEmpty else { return nil }
            let remaining = String(decoding: partial, as: UTF8.self)
            partial = Data()
            return remaining
        }
    }
}
