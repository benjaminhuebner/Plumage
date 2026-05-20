import AppKit
import Foundation

nonisolated enum XcodeRunOutcome: Sendable, Equatable {
    case launched(pid: Int32?)
    case buildFailed(exitCode: Int32)
    case launchFailed(message: String)
    case cancelled

    var isLaunched: Bool {
        if case .launched = self { return true }
        return false
    }
}

nonisolated struct XcodeRunInputs: Sendable, Equatable {
    let project: XcodeProjectRef
    let scheme: String
    let destinationArg: String
    let isSimulatorDestination: Bool
    let simulatorUDID: String?
}

nonisolated protocol AppLauncher: Sendable {
    // Returns the PID of the launched instance, or nil if the launcher can't
    // tell (e.g. test mocks or a no-pid fallback path).
    func openApp(at url: URL) async throws -> Int32?
}

nonisolated struct ProductionAppLauncher: AppLauncher {
    func openApp(at url: URL) async throws -> Int32? {
        // NSWorkspace.openApplication returns the NSRunningApplication so we
        // can both force a new instance (createsNewApplicationInstance) AND
        // track its termination via the .didTerminateApplicationNotification.
        // /usr/bin/open -n forced a new instance too but gave back no handle.
        try await openOnMain(at: url)
    }

    @MainActor
    private func openOnMain(at url: URL) async throws -> Int32 {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        return app.processIdentifier
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
                return .launched(pid: nil)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .launchFailed(message: humanReadable(error))
            }
        }

        do {
            let pid = try await appLauncher.openApp(at: appURL)
            return .launched(pid: pid)
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
