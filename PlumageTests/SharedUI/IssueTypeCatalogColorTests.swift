import SwiftUI
import Testing

@testable import Plumage

@Suite("IssueTypeCatalog color resolution")
struct IssueTypeCatalogColorTests {
    @Test("hex components parse with and without leading hash; junk is nil")
    func hexParsing() {
        let orange = IssueTypeHexColor.components(of: "#FF8800")
        #expect(orange?.red == 1)
        #expect(orange?.blue == 0)
        #expect(IssueTypeHexColor.components(of: "ff8800") != nil)
        #expect(IssueTypeHexColor.components(of: "#GGGGGG") == nil)
        #expect(IssueTypeHexColor.components(of: "#FFF") == nil)
        #expect(IssueTypeHexColor.components(of: "") == nil)
    }

    @Test("Color round-trips through the stored hex form")
    func colorHexRoundTrip() throws {
        let hex = try #require(Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6).issueTypeHexString)
        let reparsed = try #require(IssueTypeHexColor.components(of: hex))
        #expect(abs(reparsed.red - 0.2) < 0.01)
        #expect(abs(reparsed.green - 0.4) < 0.01)
        #expect(abs(reparsed.blue - 0.6) < 0.01)
    }

    @Test("a stored hex overrides the palette; without it the legacy color applies")
    func effectiveColor() {
        var catalog = IssueTypeCatalog.builtIn
        #expect(catalog.color(for: .feature) == .green)
        catalog.setColor("#336699", for: .feature)
        #expect(catalog.color(for: .feature) == Color(issueTypeHex: "#336699"))
        let custom = IssueType(rawValue: "docs")
        #expect(catalog.color(for: custom) == LabelColor.color(for: "docs"))
    }

    @Test("foreground flips by luminance for custom hex colors")
    func foregroundOnTint() {
        var catalog = IssueTypeCatalog.builtIn
        catalog.setColor("#FFEE00", for: .feature)
        #expect(catalog.foregroundOnTint(for: .feature) == .black)
        catalog.setColor("#112244", for: .feature)
        #expect(catalog.foregroundOnTint(for: .feature) == .white)
        #expect(catalog.foregroundOnTint(for: .chore) == .black)
        #expect(catalog.foregroundOnTint(for: .refactor) == .white)
    }

    @Test("an invalid stored hex degrades to the legacy color")
    func invalidHexFallsBack() {
        var catalog = IssueTypeCatalog.builtIn
        catalog.setColor("not-a-color", for: .spike)
        #expect(catalog.color(for: .spike) == .orange)
        #expect(catalog.foregroundOnTint(for: .spike) == .black)
    }
}
