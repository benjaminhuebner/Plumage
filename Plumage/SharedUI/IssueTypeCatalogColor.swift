import AppKit
import SwiftUI

extension IssueTypeCatalog {
    func color(for type: IssueType) -> Color {
        if let hex = definition(for: type)?.colorHex, let custom = Color(issueTypeHex: hex) {
            return custom
        }
        return type.color
    }

    // Custom colors pick their text side by perceived luminance; the built-in
    // tints keep their hand-verified pairings.
    func foregroundOnTint(for type: IssueType) -> Color {
        if let hex = definition(for: type)?.colorHex,
            let rgb = IssueTypeHexColor.components(of: hex)
        {
            let luminance = 0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue
            return luminance > 0.6 ? .black : .white
        }
        return type.foregroundOnTint
    }
}

extension Color {
    init?(issueTypeHex hex: String) {
        guard let rgb = IssueTypeHexColor.components(of: hex) else { return nil }
        self = Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    // nil when the color can't be resolved into sRGB (pattern/catalog colors).
    var issueTypeHexString: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

nonisolated enum IssueTypeHexColor {
    static func components(of hex: String) -> (red: Double, green: Double, blue: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
