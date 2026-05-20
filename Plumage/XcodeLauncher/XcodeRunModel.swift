import Foundation
import Observation

@Observable
@MainActor
final class XcodeRunModel {
    enum DiscoveryState: Sendable, Equatable {
        case idle
        case discovering
        case ready
        case missingToolchain
        case noProject
        case failed(message: String)
    }

    enum RunState: Sendable, Equatable {
        case idle
        case building
        case running
        case failed(message: String)

        var isBusy: Bool {
            switch self {
            case .building, .running: return true
            case .idle, .failed: return false
            }
        }
    }

    private(set) var projectRef: XcodeProjectRef?
    private(set) var schemes: [String] = []
    private(set) var selectedScheme: String?
    private(set) var destinationList: DestinationList = DestinationList(
        macSupported: false, simulatorGroups: [])
    private(set) var selectedDestination: XcodeDestination?
    private(set) var discoveryState: DiscoveryState = .idle
    private(set) var runState: RunState = .idle
    private(set) var logBuffer: [String] = []
    private(set) var multipleProjectsFound: Bool = false
    private(set) var toolchainAvailable: Bool = true

    private let xcodebuildRunner: XcodebuildRunner
    private let simulatorCatalog: SimulatorCatalog
    private let xcodebuildLocator: @Sendable () -> URL?
    private let xcrunLocator: @Sendable () -> URL?

    static let logCap = 5_000
    static let logTail = 200

    init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        simulatorCatalog: SimulatorCatalog = SimulatorCatalog(),
        xcodebuildLocator: @escaping @Sendable () -> URL? = { ToolchainLocator.xcodebuild() },
        xcrunLocator: @escaping @Sendable () -> URL? = { ToolchainLocator.xcrun() }
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.simulatorCatalog = simulatorCatalog
        self.xcodebuildLocator = xcodebuildLocator
        self.xcrunLocator = xcrunLocator
    }

    func discover(projectURL: URL) async {
        let xcodebuild = xcodebuildLocator()
        let xcrun = xcrunLocator()
        guard xcodebuild != nil, xcrun != nil else {
            applyMissingToolchain()
            return
        }
        toolchainAvailable = true

        discoveryState = .discovering
        let projects = await Task.detached(priority: .userInitiated) {
            XcodeProjectDiscovery.findAll(in: projectURL)
        }.value
        multipleProjectsFound = projects.count > 1
        guard let firstProject = projects.first else {
            projectRef = nil
            schemes = []
            selectedScheme = nil
            destinationList = DestinationList(macSupported: false, simulatorGroups: [])
            selectedDestination = nil
            discoveryState = .noProject
            return
        }
        projectRef = firstProject

        do {
            let listing = try await xcodebuildRunner.listSchemes(at: firstProject)
            schemes = listing.schemes
            if selectedScheme == nil || !listing.schemes.contains(selectedScheme ?? "") {
                selectedScheme = listing.schemes.first
            }
        } catch {
            schemes = []
            selectedScheme = nil
            discoveryState = .failed(message: Self.errorMessage(error))
            return
        }

        do {
            let sims = try await simulatorCatalog.listDevices()
            let iosSims = sims.filter { $0.runtime.platform == .iOS && $0.isAvailable }
            destinationList = DestinationList(
                macSupported: true,
                simulatorGroups: SimulatorCatalog.groupedByRuntime(iosSims)
            )
        } catch {
            destinationList = DestinationList(macSupported: true, simulatorGroups: [])
        }

        if selectedDestination == nil
            || !Self.destinationStillPresent(selectedDestination, in: destinationList)
        {
            selectedDestination = destinationList.defaultDestination
        }
        discoveryState = .ready
    }

    func reload(projectURL: URL) async {
        await discover(projectURL: projectURL)
    }

    func selectScheme(_ name: String) {
        guard schemes.contains(name) else { return }
        selectedScheme = name
    }

    func selectDestination(_ destination: XcodeDestination) {
        // My Mac is always selectable when listed; sims are validated against
        // the current destinationList so a stale UDID can't slip through.
        switch destination {
        case .myMac:
            guard destinationList.macSupported else { return }
            selectedDestination = .myMac
        case .simulator(let udid, _, _):
            let known = destinationList.simulatorGroups.flatMap(\.simulators)
                .contains { $0.udid == udid }
            guard known else { return }
            selectedDestination = destination
        }
    }

    func restoreSelections(scheme: String?, destinationID: String?) {
        if let scheme, schemes.contains(scheme) {
            selectedScheme = scheme
        }
        guard let destinationID else { return }
        if destinationID == XcodeDestination.myMac.id, destinationList.macSupported {
            selectedDestination = .myMac
            return
        }
        if destinationID.hasPrefix("sim:") {
            let udid = String(destinationID.dropFirst("sim:".count))
            for group in destinationList.simulatorGroups {
                if let sim = group.simulators.first(where: { $0.udid == udid }) {
                    selectedDestination = .simulator(
                        udid: sim.udid,
                        name: sim.name,
                        runtimeDisplayName: group.runtime.displayName
                    )
                    return
                }
            }
        }
    }

    func appendLog(_ line: String) {
        logBuffer.append(line)
        if logBuffer.count > Self.logCap {
            logBuffer = Array(logBuffer.suffix(Self.logCap))
        }
    }

    func clearLog() {
        logBuffer = []
    }

    func setRunState(_ state: RunState) {
        runState = state
    }

    var tailLog: [String] {
        Array(logBuffer.suffix(Self.logTail))
    }

    var fullLogText: String {
        logBuffer.joined(separator: "\n")
    }

    private func applyMissingToolchain() {
        toolchainAvailable = false
        projectRef = nil
        schemes = []
        selectedScheme = nil
        destinationList = DestinationList(macSupported: false, simulatorGroups: [])
        selectedDestination = nil
        discoveryState = .missingToolchain
    }

    private static func destinationStillPresent(
        _ destination: XcodeDestination?,
        in list: DestinationList
    ) -> Bool {
        guard let destination else { return false }
        switch destination {
        case .myMac: return list.macSupported
        case .simulator(let udid, _, _):
            return list.simulatorGroups.flatMap(\.simulators).contains { $0.udid == udid }
        }
    }

    private static func errorMessage(_ error: Error) -> String {
        if let error = error as? XcodeProcessRunnerError {
            return error.displayMessage
        }
        return error.localizedDescription
    }
}
