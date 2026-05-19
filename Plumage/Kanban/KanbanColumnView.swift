import SwiftUI

struct KanbanColumnView: View {
    let column: IssueColumn
    let issues: [DiscoveredIssue]
    let padding: Int
    let projectURL: URL
    let autoScroll: KanbanAutoScroll

    @Environment(\.openCreateIssue) private var openCreateIssue
    @Environment(\.kanbanFrameRegistry) private var frameRegistry

    var body: some View {
        // Keep KanbanDragController OUT of this body — the drag-aware bits
        // (placeholder slot, isDragSource flag) live in DraggableColumnBody,
        // which observes the controller in isolation. Without this split,
        // every cursor frame that resolves a new ResolvedDropTarget rebuilds
        // all four column bodies, including their header and ForEach.
        VStack(alignment: .leading, spacing: KanbanLayout.cardSpacing) {
            header
                .padding(.horizontal, 4)

            DraggableColumnBody(
                column: column,
                issues: issues,
                padding: padding,
                projectURL: projectURL,
                autoScroll: autoScroll
            )
        }
        .frame(
            minWidth: KanbanLayout.columnWidth,
            idealWidth: KanbanLayout.columnWidth,
            maxWidth: KanbanLayout.columnWidth,
            maxHeight: .infinity, alignment: .top
        )
        .contentShape(Rectangle())
        .reportColumnFrame(column: column, registry: frameRegistry)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Combine title + count so VoiceOver reads "Todo, 3 issues" as a
            // single element. Keep the plus button outside the combined
            // group so it stays an independently focusable action.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(column.name)
                    .font(.title3.weight(.semibold))
                Text("\(issues.count)")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(column.name), \(issues.count) issues")
            Spacer()
            Button {
                openCreateIssue(column.primaryStatusForCreation)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New issue")
            .accessibilityLabel("New issue in \(column.name)")
        }
    }
}

// Drag-aware body. Reads KanbanDragController so that target / drag-source
// changes only invalidate THIS view, not the parent column header or its
// surrounding frame/coordinate-space modifiers.
private struct DraggableColumnBody: View {
    let column: IssueColumn
    let issues: [DiscoveredIssue]
    let padding: Int
    let projectURL: URL
    let autoScroll: KanbanAutoScroll

    @Environment(KanbanDragController.self) private var kanbanDrag

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
                        // Anchor the card's view identity to the folder
                        // name (which survives the .valid/.invalid case
                        // flip in DiscoveredIssue). Without this, a card
                        // transitioning between cases mid-edit destroys
                        // its subtree and any in-flight DragGesture along
                        // with it.
                        .id(item.id)
                    }
                    if placeholderIndex == issues.count {
                        placeholderSlot
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollPosition(autoScroll.columnBinding(for: column))
            .scrollDisabled(kanbanDrag.isActive)
        }
    }

    private var placeholderSlot: some View {
        Color.clear
            .frame(height: KanbanLayout.cardHeight)
            .accessibilityHidden(true)
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
            projectURL: URL(filePath: "/tmp/sample"),
            autoScroll: KanbanAutoScroll()
        )
        KanbanColumnView(
            column: .done,
            issues: [],
            padding: 5,
            projectURL: URL(filePath: "/tmp/sample"),
            autoScroll: KanbanAutoScroll()
        )
    }
    .padding()
    .frame(height: 480)
    .environment(ProjectKanbanModel())
    .environment(KanbanDragController())
}
