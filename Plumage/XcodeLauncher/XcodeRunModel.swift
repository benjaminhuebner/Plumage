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

    // Identifiable wrapper for the streaming log: positional ForEach identity
    // re-identifies every visible row whenever the cap/tail window shifts.
    nonisolated struct BuildLogLine: Identifiable, Sendable, Equatable {
        let id: Int
        let text: String
    }

    private(set) var projectRef: XcodeProjectRef?
    private(set) var schemes: [String] = []
    private(set) var selectedScheme: String?
    private(set) var rawDestinationList: DestinationList = DestinationList(
        macSupported: false, simulatorGroups: [])
    private(set) var selectedDestination: XcodeDestination?
    private(set) var discoveryState: DiscoveryState = .idle
    private(set) var runState: RunState = .idle
    private(set) var logBuffer: [BuildLogLine] = []
    @ObservationIgnored private var nextLogLineID = 0
    private(set) var toolchainAvailable: Bool = true
    private(set) var schemeCompatibility: [String: SchemeCompatibility] = [:]

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
        // Task.detached for synchronous Disk-I/O off MainActor — same pattern
        // as ProjectModel.reload. `Task { }`
        // without detach would keep findAll on MainActor because the helper
        // is sync nonisolated.
        let projects = await Task.detached(priority: .userInitiated) {
            XcodeProjectDiscovery.findAll(in: projectURL)
        }.value
        guard let firstProject = projects.first else {
            projectRef = nil
            schemes = []
            selectedScheme = nil
            rawDestinationList = DestinationList(macSupported: false, simulatorGroups: [])
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
            discoveryState = .failed(message: error.localizedDescription)
            return
        }

        do {
            let sims = try await simulatorCatalog.listDevices()
            let iosSims = sims.filter { $0.runtime.platform == .iOS && $0.isAvailable }
            rawDestinationList = DestinationList(
                macSupported: true,
                simulatorGroups: SimulatorCatalog.groupedByRuntime(iosSims)
            )
        } catch {
            rawDestinationList = DestinationList(macSupported: true, simulatorGroups: [])
        }

        if let scheme = selectedScheme {
            await refreshCompatibility(for: scheme, project: firstProject)
        }

        if selectedDestination == nil
            || !Self.destinationStillPresent(selectedDestination, in: destinationList)
        {
            selectedDestination = destinationList.defaultDestination
        }
        discoveryState = .ready
    }

    private func refreshCompatibility(for scheme: String, project: XcodeProjectRef) async {
        guard schemeCompatibility[scheme] == nil else { return }
        do {
            let compat = try await xcodebuildRunner.showDestinations(
                project: project, scheme: scheme)
            schemeCompatibility[scheme] = compat
        } catch {
            // Unknown compat → leave both true so we don't accidentally hide
            // valid destinations on a transient xcodebuild hiccup.
            schemeCompatibility[scheme] = .unknown
        }
    }

    func reload(projectURL: URL) async {
        await discover(projectURL: projectURL)
    }

    func selectScheme(_ name: String) async {
        guard schemes.contains(name) else { return }
        selectedScheme = name
        if let projectRef {
            await refreshCompatibility(for: name, project: projectRef)
            ensureSelectedDestinationFitsCurrentScheme()
        }
    }

    private func ensureSelectedDestinationFitsCurrentScheme() {
        if !Self.destinationStillPresent(selectedDestination, in: destinationList) {
            selectedDestination = destinationList.defaultDestination
        }
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

    func restoreSelections(scheme: String?, destinationID: String?) async {
        if let scheme, schemes.contains(scheme), scheme != selectedScheme {
            selectedScheme = scheme
            if let projectRef, schemeCompatibility[scheme] == nil {
                await refreshCompatibility(for: scheme, project: projectRef)
                ensureSelectedDestinationFitsCurrentScheme()
            }
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
        logBuffer.append(BuildLogLine(id: nextLogLineID, text: line))
        nextLogLineID += 1
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

    var tailLog: [BuildLogLine] {
        Array(logBuffer.suffix(Self.logTail))
    }

    var destinationList: DestinationList {
        let compat = selectedScheme.flatMap { schemeCompatibility[$0] } ?? .unknown
        let macSupported = rawDestinationList.macSupported && compat.supportsMac
        let simulatorGroups = compat.supportsIOSSimulator ? rawDestinationList.simulatorGroups : []
        return DestinationList(macSupported: macSupported, simulatorGroups: simulatorGroups)
    }

    var fullLogText: String {
        logBuffer.map(\.text).joined(separator: "\n")
    }

    var installXcodeURL: URL? {
        ToolchainLocator.installXcodeURL
    }

    private func applyMissingToolchain() {
        toolchainAvailable = false
        projectRef = nil
        schemes = []
        selectedScheme = nil
        rawDestinationList = DestinationList(macSupported: false, simulatorGroups: [])
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
}
