import SwiftUI

struct MergeBranchSection: View {
    let branch: String
    let isMerging: Bool
    let errorMessage: String?
    let nonFatalNotice: String?
    let onMerge: (_ deleteBranch: Bool) -> Void

    @AppStorage("merge.deleteBranchAfter") private var deleteBranchAfter: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(.secondary)
                Text("Merge")
                    .font(.headline)
            }
            HStack(spacing: 12) {
                Button {
                    onMerge(deleteBranchAfter)
                } label: {
                    if isMerging {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                        Text("Merging…")
                    } else {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge to main")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isMerging)
                .accessibilityLabel("Merge \(branch) to main")
                Toggle("Delete branch after merge", isOn: $deleteBranchAfter)
                    .toggleStyle(.checkbox)
                    .disabled(isMerging)
                Spacer(minLength: 0)
            }
            if let errorMessage {
                errorBanner(message: errorMessage)
            }
            if let nonFatalNotice {
                nonFatalBanner(message: nonFatalNotice)
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func nonFatalBanner(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview("Idle") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        isMerging: false,
        errorMessage: nil,
        nonFatalNotice: nil,
        onMerge: { _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Merging") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        isMerging: true,
        errorMessage: nil,
        nonFatalNotice: nil,
        onMerge: { _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Error: dirty tree") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        isMerging: false,
        errorMessage: "Working tree is dirty: Plumage/Foo.swift, Bar.txt. Commit or stash before merging.",
        nonFatalNotice: nil,
        onMerge: { _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Non-fatal: branch delete failed") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        isMerging: false,
        errorMessage: nil,
        nonFatalNotice: "Merge succeeded, but branch was not deleted: not fully merged.",
        onMerge: { _ in }
    )
    .padding()
    .frame(width: 600)
}
