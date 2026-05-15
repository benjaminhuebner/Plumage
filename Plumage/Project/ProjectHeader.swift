import SwiftUI

struct ProjectHeader: View {
    let title: String
    let path: String
    let indicatorState: StatusIndicatorModel.IndicatorState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 32, weight: .semibold))
                Text(path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            StatusIndicatorView(state: indicatorState)
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
    }
}

#Preview("Header (ready)") {
    ProjectHeader(
        title: "Plumage",
        path: "/Users/me/Developer/Plumage",
        indicatorState: .ok(
            VersionCheck(
                version: SemanticVersion(major: 1, minor: 2, patch: 3),
                binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
                inSupportedRange: true
            )
        )
    )
}

#Preview("Header (missing)") {
    ProjectHeader(
        title: "Plumage",
        path: "/Users/me/Developer/Plumage",
        indicatorState: .missing
    )
}
