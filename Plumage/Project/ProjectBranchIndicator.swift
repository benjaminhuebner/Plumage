import SwiftUI

// Status-bar entry showing the current git branch — or "(detached) <sha>" in
// detached-HEAD state, nothing at all when the project is not a git repo.
// Renders nothing for the not-a-repo case so the layout collapses cleanly.
struct ProjectBranchIndicator: View {
    let state: RepoState

    var body: some View {
        if let label = state.displayLabel {
            HStack(spacing: 4) {
                Image(systemName: state.isDetached ? "exclamationmark.triangle" : "arrow.triangle.branch")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(tooltip)
            .accessibilityIdentifier("branch-indicator")
            .accessibilityLabel("Current branch")
            .accessibilityValue(label)
        }
    }

    private var tooltip: String {
        if state.isDetached, let sha = state.detachedSHA {
            return "Detached HEAD at \(sha). Use a branch checkout to make commits durable."
        }
        if let branch = state.branchName {
            return "Current branch: \(branch)"
        }
        return ""
    }
}

#Preview("Branch") {
    ProjectBranchIndicator(state: .branch("issue/00050-git-functionality"))
        .padding()
}

#Preview("Detached") {
    ProjectBranchIndicator(state: .detached(sha: "abc1234"))
        .padding()
}

#Preview("Not a repo") {
    ProjectBranchIndicator(state: .notARepo)
        .padding()
}
