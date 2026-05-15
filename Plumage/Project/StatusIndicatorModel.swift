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
        let result: IndicatorState = await Task.detached(priority: .userInitiated) {
            do {
                let check = try await runner.detectVersion()
                return check.inSupportedRange
                    ? IndicatorState.ok(check)
                    : IndicatorState.unsupported(check)
            } catch ProcessRunnerError.binaryNotFound {
                return .missing
            } catch let error as ProcessRunnerError {
                return .failed(error)
            } catch {
                return .failed(.spawnFailed(error.localizedDescription))
            }
        }.value
        self.state = result
    }
}
