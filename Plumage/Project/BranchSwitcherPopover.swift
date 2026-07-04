import SwiftUI

struct BranchSwitcherPopover: View {
    let model: ProjectGitModel
    @Binding var isPresented: Bool

    @State private var isCreating = false
    @State private var newBranchName = ""
    @State private var draggedBranch: String?
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
        BranchSwitcherRow(
            branch: branch,
            isCurrent: branch == model.repoState.branchName,
            rowHeight: Self.rowHeight,
            model: model,
            isPresented: $isPresented,
            draggedBranch: $draggedBranch)
    }
}

private struct BranchSwitcherRow: View {
    let branch: String
    let isCurrent: Bool
    let rowHeight: CGFloat
    let model: ProjectGitModel
    @Binding var isPresented: Bool
    @Binding var draggedBranch: String?

    @State private var isHovering = false
    @State private var isDropTargeted = false

    // isTargeted: can't see the payload, so the drop highlight over the
    // drag's own source row is suppressed via the shared draggedBranch state.
    private var showsDropHighlight: Bool {
        isDropTargeted && draggedBranch != branch
    }

    var body: some View {
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
                    .opacity(isCurrent ? 1 : 0)
                Text(branch)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .frame(height: rowHeight)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(0.15))
                .opacity(showsDropHighlight ? 1 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(showsDropHighlight ? 1 : 0)
        )
        .pointerStyle(.grabIdle)
        .draggable(BranchDragPayload(branchName: branch)) {
            BranchDragChip(branchName: branch)
                .onAppear { draggedBranch = branch }
        }
        .dropDestination(for: BranchDragPayload.self) { payloads, _ in
            defer { draggedBranch = nil }
            guard let payload = payloads.first, payload.branchName != branch else {
                return false
            }
            model.requestBranchMerge(source: payload.branchName, target: branch)
            isPresented = false
            return true
        } isTargeted: { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isDropTargeted = hovering
            }
        }
        .onHover { hovering in
            // Opacity-only fade — inherently Reduce-Motion-safe.
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .accessibilityIdentifier("branch-row-\(branch)")
    }
}

private struct BranchDragChip: View {
    let branchName: String

    var body: some View {
        Label(branchName, systemImage: "arrow.triangle.branch")
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            )
    }
}
