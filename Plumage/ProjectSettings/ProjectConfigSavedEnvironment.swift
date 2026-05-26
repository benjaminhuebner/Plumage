import SwiftUI

extension EnvironmentValues {
    // Fired by ProjectSettingsModel right after a successful disk write.
    // ProjectWindow uses it to refresh ProjectModel.state and
    // TerminalTabsModel.modelsConfig so the live window picks up picker
    // changes without waiting for a window reopen. Default is a no-op so
    // preview/test contexts work unwired.
    @Entry var onProjectConfigSaved: @MainActor (ProjectConfig) -> Void = { _ in }
}
