import SwiftUI

struct BranchSwitcherPopover: View {
    let model: ProjectGitModel
    @Binding var isPresented: Bool

    @State private var isCreating = false
    @State private var newBranchName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.branches.isEmpty {
                Text("No local branches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.branches, id: \.self) { branch in
                            branchRow(branch)
                        }
                    }
                    .padding(6)
                }
                // A ScrollView inside a popover collapses to near-zero ideal
                // height — size it explicitly from the row count instead.
                .frame(height: listHeight)
            }
            if let error = model.branchActionError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .accessibilityIdentifier("branch-action-error")
            }
            Divider()
            newBranchFooter
        }
        .frame(width: 280)
        .task { await model.loadBranches() }
        .onDisappear { model.clearBranchActionError() }
        .accessibilityIdentifier("branch-switcher-popover")
    }

    private var trimmedName: String {
        newBranchName.trimmingCharacters(in: .whitespaces)
    }

    private var validationHint: String? {
        if trimmedName.isEmpty { return nil }
        if !GitBranchName.isSafe(trimmedName) { return "Not a valid branch name" }
        if model.branches.contains(trimmedName) { return "Branch already exists" }
        return nil
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && validationHint == nil
    }

    @ViewBuilder
    private var newBranchFooter: some View {
        if isCreating {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Branch name", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onSubmit { createBranch() }
                    .accessibilityIdentifier("new-branch-name-field")
                if let hint = validationHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("new-branch-validation-hint")
                }
                HStack {
                    Spacer()
                    Button("Create") { createBranch() }
                        .disabled(!canCreate)
                        .accessibilityIdentifier("new-branch-create-button")
                }
            }
            .padding(8)
        } else {
            Button {
                isCreating = true
                nameFieldFocused = true
            } label: {
                Label("New Branch…", systemImage: "plus")
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityIdentifier("new-branch-button")
        }
    }

    private func createBranch() {
        guard canCreate else { return }
        let name = trimmedName
        Task {
            if await model.createBranch(name) {
                isPresented = false
            }
        }
    }

    private static let rowHeight: CGFloat = 26

    private var listHeight: CGFloat {
        min(CGFloat(model.branches.count) * (Self.rowHeight + 1) + 12, 280)
    }

    private func branchRow(_ branch: String) -> some View {
        Button {
            Task {
                if await model.checkout(branch) {
                    isPresented = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .imageScale(.small)
                    .opacity(branch == model.repoState.branchName ? 1 : 0)
                Text(branch)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .frame(height: Self.rowHeight)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("branch-row-\(branch)")
    }
}
