import SwiftUI

struct KanbanColumnView: View {
    let column: IssueColumn
    let issues: [DiscoveredIssue]
    let padding: Int
    let projectURL: URL

    @FocusedValue(\.newIssueSheetIsPresented) private var newIssueSheetIsPresented
    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(KanbanDragController.self) private var kanbanDrag

    var body: some View {
        let dragSource = kanbanDrag.state?.sourceFolderName
        let visibleIssues = issues.filter { $0.id != dragSource }
        let placeholderIndex = computePlaceholderIndex(
            dragTarget: kanbanDrag.state?.target?.target,
            column: column,
            visibleIssues: visibleIssues
        )
        let placeholderHeight = kanbanDrag.state?.sourceFrame.height ?? 100

        VStack(alignment: .leading, spacing: 8) {
            header
                .padding(.horizontal, 4)

            if visibleIssues.isEmpty && placeholderIndex == nil {
                Text("No issues")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(visibleIssues.enumerated()), id: \.element.id) { idx, item in
                            if placeholderIndex == idx {
                                placeholderSlot(height: placeholderHeight)
                            }
                            IssueCardSwitch(
                                issue: item, padding: padding, projectURL: projectURL)
                        }
                        if placeholderIndex == visibleIssues.count {
                            placeholderSlot(height: placeholderHeight)
                        }
                    }
                    .padding(.horizontal, 4)
                    .animation(.smooth(duration: 0.18), value: placeholderIndex)
                }
                .scrollDisabled(kanbanDrag.state != nil)
            }
        }
        .frame(minWidth: 240, maxWidth: 280, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .reportColumnFrame(column: column)
    }

    private func placeholderSlot(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(column.name)
                .font(.title3.weight(.semibold))
            Text("\(issues.count)")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .accessibilityLabel("\(issues.count) issues")
            Spacer()
            Button {
                newIssueSheetIsPresented?.wrappedValue = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(newIssueSheetIsPresented == nil)
            .help("New issue")
            .accessibilityLabel("New issue in \(column.name)")
            .accessibilityHint(
                newIssueSheetIsPresented == nil
                    ? "Unavailable while this project is still loading or failed to open"
                    : ""
            )
        }
    }
}

#Preview {
    HStack(alignment: .top, spacing: 12) {
        KanbanColumnView(
            column: .todo,
            issues: [
                .valid(
                    Issue(
                        id: 1,
                        folderName: "00001-walking-skeleton",
                        title: "Walking Skeleton",
                        type: .chore,
                        status: .approved,
                        created: .distantPast,
                        updated: .distantPast,
                        branch: "issue/00001-walking-skeleton",
                        labels: [],
                        model: nil,
                        goal: "Get a Plumage shell building, signing, launching."
                    )
                ),
                .valid(
                    Issue(
                        id: 7,
                        folderName: "00007-blocked-thing",
                        title: "Something blocked by another team",
                        type: .feature,
                        status: .blocked,
                        created: .distantPast,
                        updated: .distantPast,
                        branch: "issue/00007-blocked-thing",
                        labels: [],
                        model: nil,
                        goal: nil
                    )
                ),
                .invalid(
                    folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken"),
                    error: .invalidEnumValue(field: "status", value: "aproved")
                ),
            ],
            padding: 5,
            projectURL: URL(filePath: "/tmp/sample")
        )
        KanbanColumnView(
            column: .done,
            issues: [],
            padding: 5,
            projectURL: URL(filePath: "/tmp/sample")
        )
    }
    .padding()
    .frame(height: 480)
    .environment(ProjectKanbanModel())
    .environment(KanbanDragController())
}
