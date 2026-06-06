import SwiftUI

extension EnvironmentValues {
    // Fired by ProjectSettingsModel right after a successful disk write.
    // ProjectWindow uses it to refresh ProjectModel.state and
    // TerminalTabsModel.modelsConfig so the live window picks up picker
    // changes without waiting for a window reopen. Default is a no-op so
    // preview/test contexts work unwired.
    @Entry var onProjectConfigSaved: @MainActor (ProjectConfig) -> Void = { _ in }

    // Fired by ProjectSettingsModel right after a successful rename, with the
    // reloaded config and the moved bundle's URL. ProjectWindow uses it to
    // update the window title (config.name), repoint the chat session's id-store
    // to the new bundle, and refresh the project's name in Recents — all without
    // killing the running chat. Default is a no-op so preview/test contexts work
    // unwired.
    @Entry var onProjectRenamed: @MainActor (ProjectConfig, URL) -> Void = { _, _ in }
}
