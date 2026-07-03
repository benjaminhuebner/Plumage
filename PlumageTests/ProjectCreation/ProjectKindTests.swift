import Testing

@testable import Plumage

@Suite("ProjectKind")
struct ProjectKindTests {
    @Test("Seven kinds in three groups")
    func sevenKinds() {
        #expect(ProjectKind.allCases.count == 7)
        #expect(
            ProjectKind.allCases.filter { $0.group == .appleApps }
                == [.appleMultiplatform, .macOS, .iOS])
        #expect(
            ProjectKind.allCases.filter { $0.group == .serverside }
                == [.vapor, .hummingbird])
        #expect(
            ProjectKind.allCases.filter { $0.group == .other }
                == [.swiftCLI, .other])
    }

    @Test("isSwift is everything but .other")
    func isSwift() {
        for kind in ProjectKind.allCases where kind != .other {
            #expect(kind.isSwift)
        }
        #expect(!ProjectKind.other.isSwift)
    }

    @Test("projectType raw values are stable identifiers")
    func rawValues() {
        // config.json's `projectType` is `kind.rawValue`; `macOS` must match the
        // value the existing open path already reads.
        #expect(ProjectKind.macOS.rawValue == "macOS")
        #expect(ProjectKind.iOS.rawValue == "iOS")
        #expect(ProjectKind.appleMultiplatform.rawValue == "appleMultiplatform")
        #expect(ProjectKind.vapor.rawValue == "vapor")
        #expect(ProjectKind.hummingbird.rawValue == "hummingbird")
        #expect(ProjectKind.swiftCLI.rawValue == "swiftCLI")
        #expect(ProjectKind.other.rawValue == "other")
    }

    @Test("Every kind has a non-empty display name")
    func displayNames() {
        for kind in ProjectKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
        #expect(ProjectKindGroup.appleApps.displayName == "Apple Apps")
        #expect(ProjectKindGroup.serverside.displayName == "Serverside Swift")
        #expect(ProjectKindGroup.other.displayName == "Other")
    }
}
