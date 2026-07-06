import Foundation

nonisolated enum XcodeRunOutcome: Sendable, Equatable {
    case launched(pid: Int32?)
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

nonisolated protocol AppLaunching: Sendable {
    // Returns the PID of the launched instance, or nil if the launcher can't
    // tell (e.g. test mocks or a no-pid fallback path).
    func openApp(at url: URL) async throws -> Int32?
}

nonisolated struct XcodeRunSession: Sendable {
    let xcodebuildRunner: XcodebuildRunner
    let simulatorCatalog: SimulatorCatalog
    let appLauncher: any AppLaunching

    init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        simulatorCatalog: SimulatorCatalog = SimulatorCatalog(),
        appLauncher: any AppLaunching
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
            return .launchFailed(message: error.localizedDescription)
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
            return .launchFailed(message: error.localizedDescription)
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
                return .launchFailed(message: error.localizedDescription)
            }
        }

        do {
            let pid = try await appLauncher.openApp(at: appURL)
            return .launched(pid: pid)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .launchFailed(message: error.localizedDescription)
        }
    }
}
