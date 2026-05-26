import Foundation
import Observation

@Observable
@MainActor
final class ProjectModel {
    enum LoadState: Sendable {
        case loading
        case loaded(ProjectConfig)
        case failed(ConfigLoader.LoadError)
    }

    private(set) var state: LoadState = .loading

    func reload(at url: URL) async {
        let newState = await Task.detached(priority: .userInitiated) {
            Self.loadConfig(at: url)
        }.value
        self.state = newState
    }

    // In-memory state update from a known-good snapshot. ProjectSettingsModel
    // calls this right after persisting to disk so the rest of the window
    // (terminalTabs.modelsConfig, runWorkflow's workflows lookup) sees the
    // mutation without an extra disk re-read on the main actor.
    func setLoaded(_ config: ProjectConfig) {
        state = .loaded(config)
    }

    private nonisolated static func loadConfig(at url: URL) -> LoadState {
        do {
            let config = try ConfigLoader.load(at: url)
            return .loaded(config)
        } catch let error as ConfigLoader.LoadError {
            return .failed(error)
        } catch {
            return .failed(.invalidJSON(message: error.localizedDescription))
        }
    }
}
