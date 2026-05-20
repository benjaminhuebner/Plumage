import Foundation
import Observation

@Observable
@MainActor
final class XcodeRunController {
    let model: XcodeRunModel
    private(set) var runTask: Task<Void, Never>?

    private let runSession: XcodeRunSession

    init(model: XcodeRunModel, runSession: XcodeRunSession = XcodeRunSession()) {
        self.model = model
        self.runSession = runSession
    }

    func startRun() {
        guard runTask == nil else { return }
        guard let project = model.projectRef,
            let scheme = model.selectedScheme,
            let destination = model.selectedDestination
        else { return }

        model.setRunState(.building)
        model.clearLog()
        // Make the click visible immediately — xcodebuild's first stdout line
        // can be several seconds away (resolving dependencies, etc.), and
        // without a prelude line the user sees an empty log popover and may
        // think nothing happened.
        model.appendLog("→ Starting build for \(scheme) (\(destination.displayName))…")
        let inputs = XcodeRunInputs(
            project: project,
            scheme: scheme,
            destinationArg: destination.xcodebuildArgument,
            isSimulatorDestination: destination.isSimulator,
            simulatorUDID: destination.simulatorUDID
        )

        let session = runSession
        let model = model
        runTask = Task { [weak self] in
            let outcome = await session.run(inputs: inputs) { @Sendable line in
                Task { @MainActor [weak model] in
                    model?.appendLog(line)
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.applyOutcome(outcome)
                self.runTask = nil
            }
            _ = self
        }
    }

    func cancelRun() {
        runTask?.cancel()
        runTask = nil
        model.setRunState(.idle)
    }

    private func applyOutcome(_ outcome: XcodeRunOutcome) {
        switch outcome {
        case .launched:
            model.appendLog("✓ Launched.")
            model.setRunState(.running)
        case .buildFailed(let exitCode):
            let errorCount = countErrors(in: model.logBuffer)
            let message =
                errorCount > 0
                ? "Failed (\(errorCount) errors)" : "Failed (exit \(exitCode))"
            model.appendLog("✗ Build failed (exit \(exitCode)).")
            model.setRunState(.failed(message: message))
        case .launchFailed(let message):
            model.appendLog("✗ Launch failed: \(message)")
            model.setRunState(.failed(message: message))
        case .cancelled:
            model.appendLog("× Cancelled.")
            model.setRunState(.idle)
        }
    }

    private func countErrors(in lines: [String]) -> Int {
        lines.filter { $0.contains(": error:") }.count
    }
}
