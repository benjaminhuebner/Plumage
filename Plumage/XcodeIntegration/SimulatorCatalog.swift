import Foundation

nonisolated struct Simulator: Sendable, Equatable, Hashable, Identifiable {
    let udid: String
    let name: String
    let state: State
    let isAvailable: Bool
    let runtime: Runtime

    var id: String { udid }

    enum State: String, Sendable, Equatable {
        case shutdown = "Shutdown"
        case booted = "Booted"
        case other
    }

    var isBooted: Bool { state == .booted }
}

nonisolated struct Runtime: Sendable, Equatable, Hashable, Comparable {
    let identifier: String
    let displayName: String
    let platform: Platform
    let version: SemVersion?

    enum Platform: String, Sendable, Equatable {
        case iOS
        case watchOS
        case tvOS
        case visionOS
        case other
    }

    static func < (lhs: Runtime, rhs: Runtime) -> Bool {
        // Higher version first when sorted descending; here we keep ascending,
        // SimulatorCatalog sorts descending in groupedByRuntime().
        switch (lhs.version, rhs.version) {
        case (let lhsVersion?, let rhsVersion?): return lhsVersion < rhsVersion
        case (nil, _?): return true
        case (_?, nil): return false
        case (nil, nil): return lhs.displayName < rhs.displayName
        }
    }
}

nonisolated struct SemVersion: Sendable, Equatable, Hashable, Comparable {
    let major: Int
    let minor: Int

    static func < (lhs: SemVersion, rhs: SemVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        return lhs.minor < rhs.minor
    }

    var displayName: String { "\(major).\(minor)" }
}

nonisolated struct SimulatorRuntimeGroup: Sendable, Equatable {
    let runtime: Runtime
    let simulators: [Simulator]
}

nonisolated struct SimulatorCatalog: Sendable {
    let runner: any XcodeProcessRunning
    let toolchain: @Sendable () -> URL?

    init(
        runner: any XcodeProcessRunning = ProductionXcodeProcessRunner(),
        toolchain: @escaping @Sendable () -> URL? = { ToolchainLocator.xcrun() }
    ) {
        self.runner = runner
        self.toolchain = toolchain
    }

    func listDevices() async throws -> [Simulator] {
        guard let binary = toolchain() else { throw XcodeProcessRunnerError.toolchainNotFound }
        let result = try await runner.run(
            binaryURL: binary,
            args: ["simctl", "list", "devices", "--json"],
            cwd: nil
        )
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw XcodeProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        return try Self.parseDevices(data: result.stdout)
    }

    func boot(udid: String) async throws {
        guard let binary = toolchain() else { throw XcodeProcessRunnerError.toolchainNotFound }
        let result = try await runner.run(
            binaryURL: binary,
            args: ["simctl", "boot", udid],
            cwd: nil
        )
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            if Self.isAlreadyBootedMessage(stderr) || result.exitCode == 149 {
                return
            }
            throw XcodeProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
    }

    func install(udid: String, appURL: URL) async throws {
        guard let binary = toolchain() else { throw XcodeProcessRunnerError.toolchainNotFound }
        let result = try await runner.run(
            binaryURL: binary,
            args: ["simctl", "install", udid, appURL.path],
            cwd: nil
        )
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw XcodeProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
    }

    func launch(udid: String, bundleID: String) async throws {
        guard let binary = toolchain() else { throw XcodeProcessRunnerError.toolchainNotFound }
        let result = try await runner.run(
            binaryURL: binary,
            args: ["simctl", "launch", udid, bundleID],
            cwd: nil
        )
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw XcodeProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
    }

    static func groupedByRuntime(_ simulators: [Simulator]) -> [SimulatorRuntimeGroup] {
        let runtimes = Set(simulators.map { $0.runtime })
        let sortedRuntimes = runtimes.sorted(by: >)
        return sortedRuntimes.compactMap { runtime in
            let bucket =
                simulators
                .filter { $0.runtime == runtime }
                .sorted { $0.name < $1.name }
            guard !bucket.isEmpty else { return nil }
            return SimulatorRuntimeGroup(runtime: runtime, simulators: bucket)
        }
    }

    static func parseDevices(data: Data) throws -> [Simulator] {
        do {
            let envelope = try JSONDecoder().decode(DevicesEnvelope.self, from: data)
            var out: [Simulator] = []
            for (runtimeID, entries) in envelope.devices {
                let runtime = parseRuntime(identifier: runtimeID)
                for entry in entries where entry.isAvailable {
                    out.append(
                        Simulator(
                            udid: entry.udid,
                            name: entry.name,
                            state: Simulator.State(rawValue: entry.state) ?? .other,
                            isAvailable: entry.isAvailable,
                            runtime: runtime
                        )
                    )
                }
            }
            return out
        } catch let error as XcodeProcessRunnerError {
            throw error
        } catch {
            throw XcodeProcessRunnerError.parseError(error.localizedDescription)
        }
    }

    static func parseRuntime(identifier: String) -> Runtime {
        // e.g. "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
        let suffix =
            identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = suffix.split(separator: "-").map(String.init)
        guard let platformRaw = parts.first else {
            return Runtime(
                identifier: identifier,
                displayName: identifier,
                platform: .other,
                version: nil
            )
        }
        let platform = Runtime.Platform(rawValue: platformRaw) ?? .other
        let version: SemVersion?
        if parts.count >= 3,
            let major = Int(parts[1]),
            let minor = Int(parts[2])
        {
            version = SemVersion(major: major, minor: minor)
        } else {
            version = nil
        }
        let display: String
        if let version {
            display = "\(platformRaw) \(version.displayName)"
        } else {
            display = platformRaw
        }
        return Runtime(
            identifier: identifier,
            displayName: display,
            platform: platform,
            version: version
        )
    }

    private static func isAlreadyBootedMessage(_ stderr: String) -> Bool {
        // simctl boot reports "Unable to boot device in current state: Booted"
        // when the simulator already runs. Treat as success per spec.
        stderr.contains("current state: Booted")
    }

    private struct DevicesEnvelope: Decodable {
        let devices: [String: [DeviceEntry]]
    }

    private struct DeviceEntry: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool
    }
}
