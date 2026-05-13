import SwiftUI

nonisolated enum LabelColor {
    static let paletteNames: [String] = (1...8).map { "Label\($0)" }

    @MainActor
    static func color(for label: String) -> Color {
        Color(paletteNames[Int(stableHash(label) % UInt32(paletteNames.count))])
    }

    static func stableHash(_ string: String) -> UInt32 {
        var hash: UInt32 = 0x811c_9dc5
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash &*= 0x0100_0193
        }
        return hash
    }
}
