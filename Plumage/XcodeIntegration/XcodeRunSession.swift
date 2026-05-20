import Foundation

nonisolated enum XcodeRunOutcome: Sendable, Equatable {
    case launched
    case buildFailed(exitCode: Int32)
    case launchFailed(message: String)
    case cancelled
}

nonisolated struct XcodeRunInputs: Sendable, Equatable {
    let project: XcodeProjectRef
    let scheme: String
    let destinationArg: String
    let isSimulatorDestination: Bool
    let simulatorUDID: String?
}

nonisolated protocol AppLauncher: Sendable {
    func openApp(at url: URL) async throws
}

nonisolated struct ProductionAppLauncher: AppLauncher {
    private let runner: any XcodeProcessRunning
    private let openPath: URL

    init(
        runner: any XcodeProcessRunning = ProductionXcodeProcessRunner(),
        openPath: URL = URL(fileURLWithPath: "/usr/bin/open")
    ) {
        self.runner = runner
        self.openPath = openPath
    }

    func openApp(at url: URL) async throws {
        // -n forces a fresh instance even when the same bundle ID is already
        // running. Without this, dogfooding (rebuilding Plumage from within
        // Plumage) would silently just re-activate the running instance —
        // looks like "nothing happens" from the user's perspective.
        let result = try await runner.run(
            binaryURL: openPath, args: ["-n", url.path], cwd: nil)
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw XcodeProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
    }
}

nonisolated struct XcodeRunSession: Sendable {
    let xcodebuildRunner: XcodebuildRunner
    let simulatorCatalog: SimulatorCatalog
    let appLauncher: any AppLauncher

    init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        simulatorCatalog: SimulatorCatalog = SimulatorCatalog(),
        appLauncher: any AppLauncher = ProductionAppLauncher()
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.simulatorCatalog = simulatorCatalog
        self.appLauncher = appLauncher
    }

    func run(
        inputs: XcodeRunInputs,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> XcodeRunOutcome {
        do {
            let exit = try await xcodebuildRunner.build(
                project: inputs.project,
                scheme: inputs.scheme,
                destinationArg: inputs.destinationArg,
                onLine: onLine
            )
            guard exit == 0 else {
                return .buildFailed(exitCode: exit)
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .launchFailed(message: humanReadable(error))
        }

        let settings: [String: String]
        do {
            settings = try await xcodebuildRunner.showBuildSettings(
                project: inputs.project,
                scheme: inputs.scheme,
                destinationArg: inputs.destinationArg
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .launchFailed(message: humanReadable(error))
        }

        guard let appURL = XcodebuildRunner.appBundleURL(from: settings) else {
            return .launchFailed(message: "build settings missing BUILT_PRODUCTS_DIR or FULL_PRODUCT_NAME")
        }

        if inputs.isSimulatorDestination {
            guard let udid = inputs.simulatorUDID else {
                return .launchFailed(message: "simulator destination has no udid")
            }
            guard let bundleID = XcodebuildRunner.appBundleID(from: settings) else {
                return .launchFailed(message: "build settings missing PRODUCT_BUNDLE_IDENTIFIER")
            }
            do {
                try await simulatorCatalog.boot(udid: udid)
                try await simulatorCatalog.install(udid: udid, appURL: appURL)
                try await simulatorCatalog.launch(udid: udid, bundleID: bundleID)
                return .launched
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .launchFailed(message: humanReadable(error))
            }
        }

        do {
            try await appLauncher.openApp(at: appURL)
            return .launched
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .launchFailed(message: humanReadable(error))
        }
    }

    private func humanReadable(_ error: Error) -> String {
        if let error = error as? XcodeProcessRunnerError {
            return error.displayMessage
        }
        return error.localizedDescription
    }
}
