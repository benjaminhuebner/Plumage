import SwiftUI

struct BranchMergeSheet: View {
    let request: BranchMergeRequest
    let isMerging: Bool
    let error: GitMergeError?
    let noticeMessage: String?
    let onDismissError: () -> Void
    let onMerge: (_ mode: GitMergeMode, _ commitSubject: String?, _ deleteSource: Bool) -> Void
    let onClose: () -> Void

    @AppStorage("merge.deleteBranchAfter") private var deleteSourceAfter: Bool = true
    @AppStorage("merge.mode") private var mergeMode: GitMergeMode = .squash
    @State private var commitSubject: String

    init(
        request: BranchMergeRequest,
        isMerging: Bool,
        error: GitMergeError?,
        noticeMessage: String?,
        onDismissError: @escaping () -> Void,
        onMerge: @escaping (_ mode: GitMergeMode, _ commitSubject: String?, _ deleteSource: Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.request = request
        self.isMerging = isMerging
        self.error = error
        self.noticeMessage = noticeMessage
        self.onDismissError = onDismissError
        self.onMerge = onMerge
        self.onClose = onClose
        _commitSubject = State(initialValue: "Merge \(request.source) into \(request.target)")
    }

    private var trimmedSubject: String {
        commitSubject.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mergeDisabled: Bool {
        Self.mergeDisabled(
            isMerging: isMerging,
            mergeCompleted: noticeMessage != nil,
            mergeMode: mergeMode,
            trimmedSubject: trimmedSubject)
    }

    // A non-nil notice means the merge already landed — a second confirm
    // would re-merge a branch that may just have been deleted.
    nonisolated static func mergeDisabled(
        isMerging: Bool,
        mergeCompleted: Bool,
        mergeMode: GitMergeMode,
        trimmedSubject: String
    ) -> Bool {
        isMerging || mergeCompleted || (mergeMode == .squash && trimmedSubject.isEmpty)
    }

    // The runner's notFastForward message points at the PR sheet's
    // Rebase & Merge button, which this sheet deliberately doesn't have.
    nonisolated static func errorMessage(for error: GitMergeError?) -> String? {
        guard let error else { return nil }
        if case .notFastForward(let targetBranch, let sourceBranch) = error {
            return
                "Cannot fast-forward: `\(targetBranch)` has commits since `\(sourceBranch)` "
                + "was branched off. Switch to Squash to merge anyway."
        }
        return error.displayMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if mergeMode == .squash {
                TextField("Commit message", text: $commitSubject)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isMerging)
                    .accessibilityLabel("Squash commit message")
                    .accessibilityIdentifier("branch-merge-subject-field")
            }
            HStack(spacing: 12) {
                Picker("Merge mode", selection: $mergeMode) {
                    Text("Squash").tag(GitMergeMode.squash)
                    Text("Fast-forward").tag(GitMergeMode.fastForward)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(isMerging)
                .accessibilityLabel("Merge mode")
                Toggle("Delete branch after merge", isOn: $deleteSourceAfter)
                    .toggleStyle(.checkbox)
                    .disabled(isMerging)
                Spacer(minLength: 0)
            }
            if let message = Self.errorMessage(for: error) {
                errorBanner(message: message)
            }
            if let noticeMessage {
                nonFatalBanner(message: noticeMessage)
            }
            HStack(spacing: 12) {
                Spacer()
                Button(noticeMessage == nil ? "Cancel" : "Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("branch-merge-cancel-button")
                Button {
                    onMerge(
                        mergeMode,
                        mergeMode == .squash ? trimmedSubject : nil,
                        deleteSourceAfter)
                } label: {
                    if isMerging {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                        Text("Merging…")
                    } else {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(mergeDisabled)
                .accessibilityLabel("Merge \(request.source) into \(request.target)")
                .accessibilityIdentifier("branch-merge-confirm-button")
            }
        }
        .padding(20)
        .frame(width: 480)
        .onExitCommand {
            if !isMerging { onClose() }
        }
        .accessibilityIdentifier("branch-merge-sheet")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "arrow.triangle.merge")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Merge Branch")
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(request.source)
                    Image(systemName: "arrow.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(request.target)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Merge \(request.source) into \(request.target)")
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismissError) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss merge error")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("branch-merge-error-banner")
    }

    private func nonFatalBanner(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
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
        .accessibilityIdentifier("branch-merge-notice-banner")
    }
}

#Preview("Idle") {
    BranchMergeSheet(
        request: BranchMergeRequest(source: "feature/spike", target: "main"),
        isMerging: false,
        error: nil,
        noticeMessage: nil,
        onDismissError: {},
        onMerge: { _, _, _ in },
        onClose: {}
    )
}

#Preview("Merging") {
    BranchMergeSheet(
        request: BranchMergeRequest(source: "feature/spike", target: "main"),
        isMerging: true,
        error: nil,
        noticeMessage: nil,
        onDismissError: {},
        onMerge: { _, _, _ in },
        onClose: {}
    )
}

#Preview("Error: not fast-forward") {
    BranchMergeSheet(
        request: BranchMergeRequest(source: "feature/spike", target: "main"),
        isMerging: false,
        error: .notFastForward(targetBranch: "main", issueBranch: "feature/spike"),
        noticeMessage: nil,
        onDismissError: {},
        onMerge: { _, _, _ in },
        onClose: {}
    )
}

#Preview("Notice: delete failed") {
    BranchMergeSheet(
        request: BranchMergeRequest(source: "feature/spike", target: "main"),
        isMerging: false,
        error: nil,
        noticeMessage: "Merge succeeded, but branch was not deleted: not fully merged.",
        onDismissError: {},
        onMerge: { _, _, _ in },
        onClose: {}
    )
}
