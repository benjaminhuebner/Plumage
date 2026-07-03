import SwiftUI

struct MergeBranchSection: View {
    let branch: String
    let subjectPrefill: String
    let isMerging: Bool
    let blockingRunIssue: String?
    let errorMessage: String?
    let nonFatalNotice: String?
    let targetBranch: String
    let targetCandidates: [String]
    let onTargetChange: @MainActor (String) -> Void
    let onDismissError: () -> Void
    let onDismissNotice: () -> Void
    let onMerge: (_ mode: GitMergeMode, _ commitSubject: String?, _ deleteBranch: Bool) -> Void
    let onRebaseAndMerge: ((_ mode: GitMergeMode, _ commitSubject: String?, _ deleteBranch: Bool) -> Void)?

    @AppStorage("merge.deleteBranchAfter") private var deleteBranchAfter: Bool = true
    @AppStorage("merge.mode") private var mergeMode: GitMergeMode = .squash
    @State private var commitSubject: String

    init(
        branch: String,
        subjectPrefill: String,
        isMerging: Bool,
        blockingRunIssue: String? = nil,
        errorMessage: String?,
        nonFatalNotice: String?,
        targetBranch: String = "main",
        targetCandidates: [String] = [],
        onTargetChange: @escaping @MainActor (String) -> Void = { _ in },
        onDismissError: @escaping () -> Void,
        onDismissNotice: @escaping () -> Void,
        onMerge: @escaping (_ mode: GitMergeMode, _ commitSubject: String?, _ deleteBranch: Bool) -> Void,
        onRebaseAndMerge: ((_ mode: GitMergeMode, _ commitSubject: String?, _ deleteBranch: Bool) -> Void)? = nil
    ) {
        self.branch = branch
        self.subjectPrefill = subjectPrefill
        self.isMerging = isMerging
        self.blockingRunIssue = blockingRunIssue
        self.errorMessage = errorMessage
        self.nonFatalNotice = nonFatalNotice
        self.targetBranch = targetBranch
        self.targetCandidates = targetCandidates
        self.onTargetChange = onTargetChange
        self.onDismissError = onDismissError
        self.onDismissNotice = onDismissNotice
        self.onMerge = onMerge
        self.onRebaseAndMerge = onRebaseAndMerge
        _commitSubject = State(initialValue: subjectPrefill)
    }

    private var trimmedSubject: String {
        commitSubject.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mergeDisabled: Bool {
        Self.mergeDisabled(
            isMerging: isMerging,
            blockingRunIssue: blockingRunIssue,
            mergeMode: mergeMode,
            trimmedSubject: trimmedSubject)
    }

    // Evidence state is deliberately not an input: evidence is informative
    // only and must never block a merge.
    nonisolated static func mergeDisabled(
        isMerging: Bool,
        blockingRunIssue: String?,
        mergeMode: GitMergeMode,
        trimmedSubject: String
    ) -> Bool {
        isMerging || blockingRunIssue != nil || (mergeMode == .squash && trimmedSubject.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merge")
                        .font(.headline)
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if mergeMode == .squash {
                TextField("Commit message", text: $commitSubject)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isMerging)
                    .accessibilityLabel("Squash commit message")
            }
            HStack(spacing: 12) {
                Button {
                    onMerge(
                        mergeMode,
                        mergeMode == .squash ? trimmedSubject : nil,
                        deleteBranchAfter)
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
                .controlSize(.regular)
                .disabled(mergeDisabled)
                .accessibilityLabel("Merge \(branch) to \(targetBranch)")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Menu {
                    ForEach(pickerCandidates, id: \.self) { candidate in
                        Button {
                            onTargetChange(candidate)
                        } label: {
                            if candidate == targetBranch {
                                Label(candidate, systemImage: "checkmark")
                            } else {
                                Text(candidate)
                            }
                        }
                    }
                } label: {
                    Text(targetBranch)
                }
                .fixedSize()
                .disabled(isMerging)
                .accessibilityLabel("Merge target")
                .accessibilityValue(targetBranch)
                .accessibilityIdentifier("merge-target-picker")
                Picker("Merge mode", selection: $mergeMode) {
                    Text("Squash").tag(GitMergeMode.squash)
                    Text("Fast-forward").tag(GitMergeMode.fastForward)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(isMerging)
                .accessibilityLabel("Merge mode")
                Toggle("Delete branch after merge", isOn: $deleteBranchAfter)
                    .toggleStyle(.checkbox)
                    .disabled(isMerging)
                // Lives in the control row, not the banner: the trailing banner
                // edge sits under the floating Claude dock button.
                if let onRebaseAndMerge {
                    Button("Rebase & Merge") {
                        onRebaseAndMerge(
                            mergeMode,
                            mergeMode == .squash ? trimmedSubject : nil,
                            deleteBranchAfter)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(mergeDisabled)
                    .accessibilityLabel("Rebase \(branch) and merge to \(targetBranch)")
                }
                Spacer(minLength: 0)
            }
            if let blockingRunIssue {
                blockedBanner(issue: blockingRunIssue)
            }
            if let errorMessage {
                errorBanner(message: errorMessage)
            } else if onRebaseAndMerge != nil {
                rebaseRecoveryHint
            }
            if let nonFatalNotice {
                nonFatalBanner(message: nonFatalNotice)
            }
        }
    }

    // The current target always renders, even when the candidate list hasn't
    // loaded yet — a menu picker with a selection outside its options is blank.
    private var pickerCandidates: [String] {
        targetCandidates.contains(targetBranch) ? targetCandidates : [targetBranch] + targetCandidates
    }

    private var rebaseRecoveryHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
            Text("`\(targetBranch)` has commits this branch lacks — use Rebase & Merge.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func blockedBanner(issue: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "hammer.fill")
                .foregroundStyle(.secondary)
            Text("Merge disabled — implement run for `\(issue)` is active in this checkout.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Merge disabled, implement run for \(issue) is active")
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            dismissButton(action: onDismissError, label: "Dismiss merge error")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func nonFatalBanner(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            dismissButton(action: onDismissNotice, label: "Dismiss merge notice")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func dismissButton(action: @escaping () -> Void, label: String) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        // The floating Claude dock button covers the window's bottom-right
        // corner — without the inset the X is visible but unclickable.
        .padding(.trailing, 36)
    }
}

#Preview("Idle") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        subjectPrefill: "Add merge button to PR view",
        isMerging: false,
        errorMessage: nil,
        nonFatalNotice: nil,
        onDismissError: {},
        onDismissNotice: {},
        onMerge: { _, _, _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Empty subject") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        subjectPrefill: "",
        isMerging: false,
        errorMessage: nil,
        nonFatalNotice: nil,
        onDismissError: {},
        onDismissNotice: {},
        onMerge: { _, _, _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Merging") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        subjectPrefill: "Add merge button to PR view",
        isMerging: true,
        errorMessage: nil,
        nonFatalNotice: nil,
        onDismissError: {},
        onDismissNotice: {},
        onMerge: { _, _, _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Blocked by implement run") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        subjectPrefill: "Add merge button to PR view",
        isMerging: false,
        blockingRunIssue: "00043-other-issue",
        errorMessage: nil,
        nonFatalNotice: nil,
        onDismissError: {},
        onDismissNotice: {},
        onMerge: { _, _, _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Error: dirty tree") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        subjectPrefill: "Add merge button to PR view",
        isMerging: false,
        errorMessage: "Working tree is dirty: Plumage/Foo.swift, Bar.txt. Commit or stash before merging.",
        nonFatalNotice: nil,
        onDismissError: {},
        onDismissNotice: {},
        onMerge: { _, _, _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Error: not fast-forward") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        subjectPrefill: "Add merge button to PR view",
        isMerging: false,
        errorMessage:
            "Cannot fast-forward: `main` has commits since `issue/00042-pr-merge-button` "
            + "was branched off. Use Rebase & Merge, or rebase manually.",
        nonFatalNotice: nil,
        onDismissError: {},
        onDismissNotice: {},
        onMerge: { _, _, _ in },
        onRebaseAndMerge: { _, _, _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Rebase recovery, banner dismissed") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        subjectPrefill: "Add merge button to PR view",
        isMerging: false,
        errorMessage: nil,
        nonFatalNotice: nil,
        onDismissError: {},
        onDismissNotice: {},
        onMerge: { _, _, _ in },
        onRebaseAndMerge: { _, _, _ in }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Non-fatal: branch delete failed") {
    MergeBranchSection(
        branch: "issue/00042-pr-merge-button",
        subjectPrefill: "Add merge button to PR view",
        isMerging: false,
        errorMessage: nil,
        nonFatalNotice: "Merge succeeded, but branch was not deleted: not fully merged.",
        onDismissError: {},
        onDismissNotice: {},
        onMerge: { _, _, _ in }
    )
    .padding()
    .frame(width: 600)
}
