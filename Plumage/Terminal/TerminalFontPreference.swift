import AppKit

nonisolated enum TerminalFontPreference {
    static let defaultsKey = "terminal.fontSize"
    static let defaultSize: Double = 12
    static let minSize: Double = 9
    static let maxSize: Double = 24

    static func clamped(_ size: Double) -> Double {
        min(max(size, minSize), maxSize)
    }

    static func increased(from size: Double) -> Double {
        clamped(size + 1)
    }

    static func decreased(from size: Double) -> Double {
        clamped(size - 1)
    }

    static func font(ofSize size: Double) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: clamped(size), weight: .regular)
    }
}
