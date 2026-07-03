nonisolated enum ProjectKind: String, CaseIterable, Codable, Hashable, Sendable {
    case appleMultiplatform
    case macOS
    case iOS
    case vapor
    case hummingbird
    case swiftCLI
    case other

    var group: ProjectKindGroup {
        switch self {
        case .appleMultiplatform, .macOS, .iOS: .appleApps
        case .vapor, .hummingbird: .serverside
        case .swiftCLI, .other: .other
        }
    }

    var isSwift: Bool { self != .other }

    var displayName: String {
        switch self {
        case .appleMultiplatform: "Multiplatform App"
        case .macOS: "macOS App"
        case .iOS: "iOS App"
        case .vapor: "Vapor"
        case .hummingbird: "Hummingbird"
        case .swiftCLI: "Swift CLI"
        case .other: "Other"
        }
    }
}

nonisolated enum ProjectKindGroup: String, CaseIterable, Codable, Hashable, Sendable {
    case appleApps
    case serverside
    case other

    var displayName: String {
        switch self {
        case .appleApps: "Apple Apps"
        case .serverside: "Serverside Swift"
        case .other: "Other"
        }
    }
}
