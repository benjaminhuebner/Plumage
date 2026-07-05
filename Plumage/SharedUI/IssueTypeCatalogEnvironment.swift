import SwiftUI

// Read-only value snapshot for consumers (menus, gating, pickers). PlumageApp
// re-injects it whenever the observable catalog model mutates; previews and
// tests get the built-in catalog without needing the model in the environment.
extension EnvironmentValues {
    @Entry var issueTypeCatalog: IssueTypeCatalog = .builtIn
}
