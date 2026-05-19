import SwiftUI

struct ProjectStatusBar: View {
    let indicatorState: StatusIndicatorModel.IndicatorState

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            StatusIndicatorView(state: indicatorState)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }
}

#Preview("StatusBar (ok)") {
    ProjectStatusBar(
        indicatorState: .ok(
            VersionCheck(
                version: SemanticVersion(major: 1, minor: 2, patch: 3),
                binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
                inSupportedRange: true
            )
        )
    )
    .frame(width: 720)
}

#Preview("StatusBar (missing)") {
    ProjectStatusBar(indicatorState: .missing)
        .frame(width: 720)
}
