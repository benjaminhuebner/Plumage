import Foundation
import SwiftUI
import Testing

@testable import Plumage

@Suite("KanbanCardTap")
@MainActor
struct KanbanCardTapTests {
    @Test("SpecRoute round-trips through NavigationPath")
    func navigationPathAppend() throws {
        var path = NavigationPath()
        #expect(path.isEmpty)

        path.append(SpecRoute.spec(folderName: "00003-foo"))

        #expect(path.count == 1)
    }

    @Test("SpecRoute equality is value-based on folderName")
    func specRouteEquality() {
        #expect(SpecRoute.spec(folderName: "00003-foo") == SpecRoute.spec(folderName: "00003-foo"))
        #expect(SpecRoute.spec(folderName: "00003-foo") != SpecRoute.spec(folderName: "00004-bar"))
    }

    @Test("SpecRoute is Codable round-trippable")
    func specRouteCodable() throws {
        let route = SpecRoute.spec(folderName: "00007-new-issue")
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(SpecRoute.self, from: data)
        #expect(decoded == route)
    }
}
