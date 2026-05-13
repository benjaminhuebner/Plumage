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
