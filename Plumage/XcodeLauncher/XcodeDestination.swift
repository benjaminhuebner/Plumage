nonisolated enum XcodeDestination: Sendable, Equatable, Hashable, Identifiable {
    case myMac
    case simulator(udid: String, name: String, runtimeDisplayName: String)

    var id: String {
        switch self {
        case .myMac: return "my-mac"
        case .simulator(let udid, _, _): return "sim:\(udid)"
        }
    }

    var displayName: String {
        switch self {
        case .myMac: return "My Mac"
        case .simulator(_, let name, let runtime): return "\(name) (\(runtime))"
        }
    }

    var xcodebuildArgument: String {
        switch self {
        case .myMac: return "platform=macOS"
        case .simulator(let udid, _, _): return "id=\(udid)"
        }
    }

    var isSimulator: Bool {
        if case .simulator = self { return true }
        return false
    }

    var simulatorUDID: String? {
        if case .simulator(let udid, _, _) = self { return udid }
        return nil
    }
}

nonisolated struct DestinationList: Sendable, Equatable {
    let macSupported: Bool
    let simulatorGroups: [SimulatorRuntimeGroup]

    var isEmpty: Bool {
        !macSupported && simulatorGroups.isEmpty
    }

    var defaultDestination: XcodeDestination? {
        if macSupported {
            return .myMac
        }
        // Pick the newest simulator of the highest runtime.
        guard let firstGroup = simulatorGroups.first,
            let firstSim = firstGroup.simulators.first
        else { return nil }
        return .simulator(
            udid: firstSim.udid,
            name: firstSim.name,
            runtimeDisplayName: firstGroup.runtime.displayName
        )
    }
}
