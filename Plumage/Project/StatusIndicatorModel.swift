import Foundation
import Observation

@Observable
@MainActor
final class StatusIndicatorModel {
    enum IndicatorState: Sendable, Equatable {
        case loading
        case ok(VersionCheck)
        case unsupported(VersionCheck)
        case missing
        case failed(ProcessRunnerError)
    }

    private(set) var state: IndicatorState = .loading

    func detect(using runner: any ProcessRunning) async {
        // No Task.detached here on purpose: SwiftUI's .task(id:) must be able to
        // cancel detection when the project window closes, so the spawn's
        // SIGTERM-then-SIGKILL chain in ProductionProcessRunner fires.
        do {
            let check = try await runner.detectVersion()
            state = check.inSupportedRange ? .ok(check) : .unsupported(check)
        } catch ProcessRunnerError.binaryNotFound {
            state = .missing
        } catch let error as ProcessRunnerError {
            state = .failed(error)
        } catch is CancellationError {
            // Leave state as-is; the window is going away.
        } catch {
            state = .failed(.spawnFailed(error.localizedDescription))
        }
    }
}
