import SwiftUI

struct GitCommitView: View {
    @Bindable var model: GitCommitModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                fileList
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                diffPanel
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            Divider()
            commitFooter
        }
        .frame(minWidth: 780, minHeight: 520)
        .task { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.commitState) { _, new in
            if case .done = new { onDismiss() }
        }
    }

    @ViewBuilder
    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.loadState {
            case .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if model.files.isEmpty {
                    emptyFileList
                } else {
                    fileTable
                }
            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load file status").font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
    }

    @ViewBuilder
    private var emptyFileList: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("Nothing to commit").foregroundStyle(.secondary)
            Text("Your working tree is clean.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var fileTable: some View {
        List(selection: selectionBinding) {
            ForEach(model.files) { file in
                FileRow(
                    file: file,
                    isStaged: model.stagedPaths.contains(file.path),
                    onToggle: { model.toggleStaged(file.path) }
                )
                .tag(file.path)
            }
        }
        .listStyle(.inset)
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedPath },
            set: { new in model.selectFile(new) }
        )
    }

    @ViewBuilder
    private var diffPanel: some View {
        if model.selectedPath == nil {
            VStack {
                Text("Select a file to preview")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.diffPreview.isEmpty {
            VStack {
                Text("No diff to display")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.diffPreview, id: \.path) { file in
                        CommitDiffFileSection(file: file)
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var commitFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .error(let message) = model.commitState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            HStack(alignment: .top, spacing: 12) {
                TextEditor(text: $model.message)
                    .font(.body.monospaced())
                    .frame(minHeight: 60, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator)
                    )
                VStack {
                    Button("Commit") {
                        Task { await model.commit() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!model.canCommit)
                    Button("Cancel", role: .cancel) { onDismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(12)
    }
}

private struct FileRow: View {
    let file: GitFileStatus
    let isStaged: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: stagedBinding) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            Text(String(file.badge))
                .font(.caption.monospaced())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(badgeBackground)
                .foregroundStyle(badgeForeground)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(file.path)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    // Side-effect-only: the setter ignores its value and routes to the model —
    // no mirrored local state to keep in sync.
    private var stagedBinding: Binding<Bool> {
        Binding(get: { isStaged }, set: { _ in onToggle() })
    }

    private var badgeBackground: Color {
        switch file.badge {
        case "M": return .yellow.opacity(0.25)
        case "A": return .green.opacity(0.25)
        case "D": return .red.opacity(0.25)
        case "R", "C": return .blue.opacity(0.25)
        case "U": return .orange.opacity(0.3)
        case "?": return .gray.opacity(0.2)
        default: return .gray.opacity(0.15)
        }
    }

    private var badgeForeground: Color {
        .primary
    }
}

private struct CommitDiffFileSection: View {
    let file: FileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.path)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                CommitDiffHunk(hunk: hunk)
            }
        }
    }
}

private struct CommitDiffHunk: View {
    let hunk: Hunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunkHeader)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            DiffHunkLinesView(hunk: hunk, style: .compact)
                .equatable()
        }
        .padding(8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var hunkHeader: String {
        "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
    }
}
