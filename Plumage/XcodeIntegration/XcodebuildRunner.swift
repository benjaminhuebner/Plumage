import Foundation

nonisolated struct XcodebuildListing: Sendable, Equatable {
    let projectName: String
    let schemes: [String]
}

nonisolated struct SchemeCompatibility: Sendable, Equatable {
    let supportsMac: Bool
    let supportsIOSSimulator: Bool

    static let unknown = SchemeCompatibility(supportsMac: true, supportsIOSSimulator: true)
}

nonisolated struct XcodebuildRunner: Sendable {
    let runner: any XcodeProcessRunning
    let toolchain: @Sendable () -> URL?

    init(
        runner: any XcodeProcessRunning = ProductionXcodeProcessRunner(),
        toolchain: @escaping @Sendable () -> URL? = { ToolchainLocator.xcodebuild() }
    ) {
        self.runner = runner
        self.toolchain = toolchain
    }

    func build(
        project: XcodeProjectRef,
        scheme: String,
        destinationArg: String,
        configuration: String = "Debug",
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        guard let binary = toolchain() else { throw XcodeProcessRunnerError.toolchainNotFound }
        let args: [String] = [
            project.listFlag, project.url.path,
            "-scheme", scheme,
            "-destination", destinationArg,
            "-configuration", configuration,
            "build",
        ]
        return try await runner.stream(binaryURL: binary, args: args, cwd: nil, onLine: onLine)
    }

    func showBuildSettings(
        project: XcodeProjectRef,
        scheme: String,
        destinationArg: String,
        configuration: String = "Debug"
    ) async throws -> [String: String] {
        guard let binary = toolchain() else { throw XcodeProcessRunnerError.toolchainNotFound }
        let args: [String] = [
            project.listFlag, project.url.path,
            "-scheme", scheme,
            "-destination", destinationArg,
            "-configuration", configuration,
            "-showBuildSettings",
        ]
        let result = try await runner.run(binaryURL: binary, args: args, cwd: nil)
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw XcodeProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        return Self.parseBuildSettings(String(decoding: result.stdout, as: UTF8.self))
    }

    static func parseBuildSettings(_ stdout: String) -> [String: String] {
        // xcodebuild -showBuildSettings produces "<INDENT>KEY = VALUE" lines.
        var settings: [String: String] = [:]
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let equalsRange = trimmed.range(of: " = ") else { continue }
            let key = String(trimmed[..<equalsRange.lowerBound])
            let value = String(trimmed[equalsRange.upperBound...])
            guard !key.isEmpty else { continue }
            // First occurrence wins; the build-settings dump prefixes lines
            // by target, but the top section is the active scheme target.
            if settings[key] == nil {
                settings[key] = value
            }
        }
        return settings
    }

    static func appBundleURL(from settings: [String: String]) -> URL? {
        guard let dir = settings["BUILT_PRODUCTS_DIR"],
            let name = settings["FULL_PRODUCT_NAME"]
        else { return nil }
        return URL(fileURLWithPath: dir).appendingPathComponent(name)
    }

    static func appBundleID(from settings: [String: String]) -> String? {
        settings["PRODUCT_BUNDLE_IDENTIFIER"]
    }

    func showDestinations(
        project: XcodeProjectRef,
        scheme: String
    ) async throws -> SchemeCompatibility {
        guard let binary = toolchain() else { throw XcodeProcessRunnerError.toolchainNotFound }
        let args: [String] = [
            project.listFlag, project.url.path,
            "-scheme", scheme,
            "-showdestinations",
        ]
        let result = try await runner.run(binaryURL: binary, args: args, cwd: nil)
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw XcodeProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        return Self.parseSchemeCompatibility(String(decoding: result.stdout, as: UTF8.self))
    }

    static func parseSchemeCompatibility(_ stdout: String) -> SchemeCompatibility {
        // -showdestinations lists `{ platform:<X>, ... }` rows after the
        // "Available destinations for the \"<scheme>\" scheme:" header.
        // We treat a row as relevant only if it actually contains "platform:";
        // unrelated `{`-starting lines (e.g. JSON wrapper bracket from a wrong
        // mock injection in tests) don't disable destination filtering.
        var sawMac = false
        var sawIOSSim = false
        var sawPlatform = false
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.contains("platform:") else { continue }
            sawPlatform = true
            if trimmed.contains("platform:macOS") {
                sawMac = true
            }
            if trimmed.contains("platform:iOS Simulator") {
                sawIOSSim = true
            }
        }
        // Fail-open: if we can't see ANY platform row, default to .unknown so
        // the picker keeps showing whatever the simulator catalog already
        // discovered.
        guard sawPlatform else { return .unknown }
        return SchemeCompatibility(supportsMac: sawMac, supportsIOSSimulator: sawIOSSim)
    }

    func listSchemes(at project: XcodeProjectRef) async throws -> XcodebuildListing {
        guard let binary = toolchain() else { throw XcodeProcessRunnerError.toolchainNotFound }
        let args = [project.listFlag, project.url.path, "-list", "-json"]
        let result = try await runner.run(binaryURL: binary, args: args, cwd: nil)
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw XcodeProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        return try Self.parseListing(data: result.stdout)
    }

    static func parseListing(data: Data) throws -> XcodebuildListing {
        let decoder = JSONDecoder()
        do {
            let envelope = try decoder.decode(ListEnvelope.self, from: data)
            if let project = envelope.project {
                return XcodebuildListing(projectName: project.name, schemes: project.schemes)
            }
            if let workspace = envelope.workspace {
                return XcodebuildListing(projectName: workspace.name, schemes: workspace.schemes)
            }
            throw XcodeProcessRunnerError.parseError(
                "no `project` or `workspace` key in xcodebuild -list -json output")
        } catch let error as XcodeProcessRunnerError {
            throw error
        } catch {
            throw XcodeProcessRunnerError.parseError(error.localizedDescription)
        }
    }

    private struct ListEnvelope: Decodable {
        let project: ProjectBody?
        let workspace: WorkspaceBody?
    }

    private struct ProjectBody: Decodable {
        let name: String
        let schemes: [String]
    }

    private struct WorkspaceBody: Decodable {
        let name: String
        let schemes: [String]
    }
}
