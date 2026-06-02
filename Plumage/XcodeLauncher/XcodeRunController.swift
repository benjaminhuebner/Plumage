import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class XcodeRunController {
    let model: XcodeRunModel
    private(set) var runTask: Task<Void, Never>?
    private(set) var launchedPID: Int32?

    private let runSession: XcodeRunSession
    private var terminationObserver: NSObjectProtocol?

    init(
        model: XcodeRunModel,
        runSession: XcodeRunSession = XcodeRunSession(appLauncher: ProductionAppLauncher())
    ) {
        self.model = model
        self.runSession = runSession
    }

    // isolated deinit (Swift 6.2) so we can touch the @MainActor stored
    // observer reference directly. Same pattern as ClaudeSession.
    isolated deinit {
        if let observer = terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func startRun() {
        guard runTask == nil else { return }
        guard let project = model.projectRef,
            let scheme = model.selectedScheme,
            let destination = model.selectedDestination
        else { return }

        // Drop any prior termination observer — a fresh run replaces the
        // previously-launched instance regardless of whether it's still alive.
        stopObservingTermination()
        launchedPID = nil

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
        // `model` is captured locally so log appends survive regardless of the
        // controller's lifetime. self is captured WEAKLY: if ProjectWindow's
        // onDisappear is skipped on an abnormal window close, the controller
        // (and its up-to-5000-line log buffer) can still dealloc instead of
        // being pinned alive until xcodebuild exits — isolated deinit then
        // cancels runTask. applyOutcome is simply skipped if self is gone,
        // which is correct: nothing is observing the outcome anymore.
        runTask = Task { [weak self] in
            let outcome = await session.run(inputs: inputs) { @Sendable line in
                Task { @MainActor in
                    model.appendLog(line)
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.applyOutcome(outcome)
                self.runTask = nil
            }
        }
    }

    func cancelRun() {
        switch model.runState {
        case .running:
            // Stop button on a running app terminates the launched instance.
            // Drop the observer + reset state synchronously: a window-close
            // while a run is active otherwise leaves the NSWorkspace observer
            // dangling until SwiftUI deallocs the @State-held controller, and
            // it can fire against a stale handler.
            stopObservingTermination()
            if let pid = launchedPID,
                let app = NSRunningApplication(processIdentifier: pid)
            {
                model.appendLog("× Stopping app…")
                _ = app.terminate()
                // Force-kill if it doesn't go down within 2 seconds — same
                // grace-period pattern we use for xcodebuild itself. The pid
                // is captured locally so launchedPID = nil below doesn't race.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if let app = NSRunningApplication(processIdentifier: pid),
                        !app.isTerminated
                    {
                        _ = app.forceTerminate()
                    }
                }
            }
            launchedPID = nil
            model.setRunState(.idle)
        case .building:
            runTask?.cancel()
            runTask = nil
            model.setRunState(.idle)
        case .idle, .failed:
            // No-op — nothing to cancel.
            break
        }
    }

    private func applyOutcome(_ outcome: XcodeRunOutcome) {
        switch outcome {
        case .launched(let pid):
            model.appendLog("✓ Launched.")
            launchedPID = pid
            if let pid {
                observeTermination(pid: pid)
            }
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

    private func observeTermination(pid: Int32) {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                app.processIdentifier == pid
            else { return }
            // Hop to MainActor — the observer block isn't isolated.
            Task { @MainActor [weak self] in
                self?.handleLaunchedAppTerminated()
            }
        }
    }

    private func stopObservingTermination() {
        if let observer = terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            terminationObserver = nil
        }
    }

    private func handleLaunchedAppTerminated() {
        stopObservingTermination()
        launchedPID = nil
        // Only mutate state if we were still in .running — a /clear or a new
        // build that landed first would have already set state elsewhere.
        if case .running = model.runState {
            model.appendLog("◦ App exited.")
            model.setRunState(.idle)
        }
    }
}
