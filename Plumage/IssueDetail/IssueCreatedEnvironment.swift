import SwiftUI

extension EnvironmentValues {
    @Entry var onIssueCreated: (String) -> Void = { _ in }
}
