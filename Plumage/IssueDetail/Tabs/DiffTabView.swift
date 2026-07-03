import LanguageSupport
import SwiftUI

struct DiffTabView: View {
    @Bindable var model: DiffTabModel
    var findings: ReviewFindingsModel?
    @AppStorage(DiffViewMode.storageKey) private var viewMode: DiffViewMode = .unified

    var body: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
        case .empty:
            emptyState
        case .diff(let files):
            diffContent(files)
        case .error(let error):
            errorState(error)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        BodyTabEmptyState(
            symbol: "checkmark.diamond",
            title: "No changes on this branch",
            detail: "Commit something to see the diff."
        )
    }

    @ViewBuilder
    private func errorState(_ error: GitDiffError) -> some View {
        BodyTabEmptyState(
            symbol: "exclamationmark.triangle",
            title: "Could not load diff",
            detail: error.displayMessage
        )
    }

    @ViewBuilder
    private func diffContent(_ files: [FileDiff]) -> some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                if let findings {
                    DiffFindingsSummary(model: findings, files: files) { anchor in
                        jump(to: anchor, in: files, proxy: proxy)
                    }
                }
                diffList(files)
            }
        }
    }

    // Two-step scroll: land on the file section first so the lazy rows in
    // between materialize, then home in on the line anchor.
    private func jump(to anchor: DiffLineAnchor, in files: [FileDiff], proxy: ScrollViewProxy) {
        guard files.contains(where: { $0.path == anchor.file }) else { return }
        withAnimation { proxy.scrollTo(anchor.file, anchor: .top) }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation { proxy.scrollTo(anchor, anchor: .center) }
        }
    }

    @ViewBuilder
    private func diffList(_ files: [FileDiff]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // id by path so FileDiffSection's @State (isExpanded) tracks
                // the file, not its position in the list. Without this a
                // reorder or insertion would silently transfer the user's
                // collapse state to a different file.
                ForEach(files, id: \.path) { file in
                    FileDiffSection(file: file, viewMode: viewMode, findings: findings)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(minHeight: 240)
    }
}

private struct FileDiffSection: View {
    let file: FileDiff
    let viewMode: DiffViewMode
    var findings: ReviewFindingsModel?
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(file.hunks.enumerated()), id: \.offset) { offset, hunk in
                    if offset > 0 {
                        HunkSeparator()
                    }
                    HunkView(hunk: hunk, viewMode: viewMode, commenting: commenting)
                }
            }
            .padding(.top, 4)
        } label: {
            FileDiffHeader(file: file)
        }
    }

    private var commenting: DiffCommenting? {
        guard let findings else { return nil }
        return DiffCommenting(file: file.path, model: findings)
    }
}

private struct FileDiffHeader: View {
    let file: FileDiff

    var body: some View {
        HStack(spacing: 10) {
            statusBadge
            Text(file.path)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            additionsRemovals
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(badgeText)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeText: String {
        switch file.status {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        case .binary: return "Binary"
        case .submodule: return "Submodule"
        }
    }

    private var badgeColor: Color {
        switch file.status {
        case .added: return .green
        case .modified: return .blue
        case .deleted: return .red
        case .renamed: return .orange
        case .copied: return .orange
        case .binary: return .gray
        case .submodule: return .purple
        }
    }

    @ViewBuilder
    private var additionsRemovals: some View {
        HStack(spacing: 6) {
            Text("+\(file.addedCount)")
                .foregroundStyle(.green)
            Text("−\(file.removedCount)")
                .foregroundStyle(.red)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

private struct HunkSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(height: 1)
    }
}

private struct HunkView: View {
    let hunk: Hunk
    let viewMode: DiffViewMode
    var commenting: DiffCommenting?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hunkHeader
            switch viewMode {
            case .unified:
                DiffHunkLinesView(hunk: hunk, style: .detail, commenting: commenting)
                    .equatable()
            case .sideBySide:
                SideBySideHunkView(hunk: hunk, style: .detail, commenting: commenting)
                    .equatable()
            }
        }
    }

    @ViewBuilder
    private var hunkHeader: some View {
        HStack(spacing: 6) {
            Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if !hunk.headerContext.isEmpty {
                Text(hunk.headerContext)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }
}
