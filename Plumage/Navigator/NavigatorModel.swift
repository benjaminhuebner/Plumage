import Foundation

@MainActor
@Observable
final class NavigatorModel {
    private(set) var docs: [URL] = []
    private(set) var hooks: [URL] = []
    private(set) var skills: [SkillNode] = []
    private(set) var loadError: String?

    func reload(projectURL: URL) async {
        let snapshot = await Task.detached(priority: .userInitiated) { () -> Snapshot in
            var snap = Snapshot()
            do {
                snap.docs = try ClaudeProjectFiles.enumerateDocs(projectURL: projectURL)
                snap.hooks = try ClaudeProjectFiles.enumerateHooks(projectURL: projectURL)
                snap.skills = try ClaudeProjectFiles.enumerateSkills(projectURL: projectURL)
            } catch {
                snap.error = error.localizedDescription
            }
            return snap
        }.value
        self.docs = snapshot.docs
        self.hooks = snapshot.hooks
        self.skills = snapshot.skills
        self.loadError = snapshot.error
    }
}

private struct Snapshot: Sendable {
    var docs: [URL] = []
    var hooks: [URL] = []
    var skills: [SkillNode] = []
    var error: String?
}
