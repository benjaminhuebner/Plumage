import SwiftUI

struct KanbanColumnView: View {
    let column: IssueColumn
    let issues: [DiscoveredIssue]
    let padding: Int
    let projectURL: URL
    @Binding var scrollPosition: ScrollPosition

    @FocusedValue(\.newIssueSheetIsPresented) private var newIssueSheetIsPresented
    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(KanbanDragController.self) private var kanbanDrag
    @Environment(\.kanbanFrameRegistry) private var frameRegistry

    var body: some View {
        // Keep ALL issues in the ForEach — even the source. Removing the
        // source IssueCardSwitch from the array would destroy its view, and
        // the attached DragGesture would die mid-drag. IssueCardSwitch
        // collapses to height 0 + opacity 0 while it is the drag source, so
        // its view identity (and the gesture) survives the drag.
        let dragSource = kanbanDrag.sourceFolderName
        let placeholderIndex = computePlaceholderIndex(
            dragTarget: kanbanDrag.target?.target,
            column: column,
            visibleIssues: issues
        )

        VStack(alignment: .leading, spacing: KanbanLayout.cardSpacing) {
            header
                .padding(.horizontal, 4)

            if issues.isEmpty && placeholderIndex == nil {
                Text("No issues")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: KanbanLayout.cardSpacing) {
                        ForEach(Array(issues.enumerated()), id: \.element.id) { idx, item in
                            if placeholderIndex == idx {
                                placeholderSlot
                            }
                            IssueCardSwitch(
                                issue: item,
                                padding: padding,
                                projectURL: projectURL,
                                isDragSource: item.id == dragSource
                            )
                        }
                        if placeholderIndex == issues.count {
                            placeholderSlot
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollPosition($scrollPosition)
                .scrollDisabled(kanbanDrag.isActive)
            }
        }
        // Pin every column to a fixed width so empty columns and full
        // columns match. `maxHeight: .infinity` lets the column stretch to
        // fill the kanban's vertical space.
        .frame(
            minWidth: KanbanLayout.columnWidth,
            idealWidth: KanbanLayout.columnWidth,
            maxWidth: KanbanLayout.columnWidth,
            maxHeight: .infinity, alignment: .top
        )
        .contentShape(Rectangle())
        .reportColumnFrame(column: column, registry: frameRegistry)
    }

    private var placeholderSlot: some View {
        Color.clear
            .frame(height: KanbanLayout.cardHeight)
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
    @Previewable @State var todoScroll = ScrollPosition()
    @Previewable @State var doneScroll = ScrollPosition()
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
            projectURL: URL(filePath: "/tmp/sample"),
            scrollPosition: $todoScroll
        )
        KanbanColumnView(
            column: .done,
            issues: [],
            padding: 5,
            projectURL: URL(filePath: "/tmp/sample"),
            scrollPosition: $doneScroll
        )
    }
    .padding()
    .frame(height: 480)
    .environment(ProjectKanbanModel())
    .environment(KanbanDragController())
}
