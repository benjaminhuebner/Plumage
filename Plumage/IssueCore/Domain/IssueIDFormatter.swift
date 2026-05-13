import Foundation

nonisolated enum IssueIDFormatter {
    static func padded(_ id: Int, width: Int) -> String {
        String(format: "%0\(max(width, 1))d", id)
    }

    static func paddedOrPlaceholder(_ id: Int?, width: Int) -> String {
        if let id { return padded(id, width: width) }
        return String(repeating: "?", count: max(width, 1))
    }
}
