import SwiftUI

struct IssueCardSwitch: View {
    let issue: DiscoveredIssue
    let padding: Int
    let projectURL: URL
    var isDragSource: Bool = false

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(RunStatusModel.self) private var runStatus
    // Drag controller is intentionally NOT read here. The card's "am I the
    // drag source?" answer arrives as the `isDragSource` prop from the
    // parent DraggableColumnBody, and the drag gesture itself lives in
    // CardInteraction which has its own @Environment read. Keeping a
    // controller dependency on IssueCardSwitch would invalidate every
    // visible cell on drag-start/end (controller.isActive flips), which
    // is N×4 unnecessary body re-evals at lift-off.
    @Environment(\.openSpec) private var openSpec
    @Environment(\.runWorkflow) private var runWorkflow
    @Environment(\.workflowCommandIsEmpty) private var workflowCommandIsEmpty
    @Environment(\.kanbanFrameRegistry) private var frameRegistry
    @FocusedValue(\.specEditorDirtyFolderName) private var dirtyFolderName: String?

    var body: some View {
        switch issue {
        case .valid(let value):
            validBody(value)
        case .invalid(let folder, let error):
            InvalidIssueCardView(folder: folder, error: error, padding: padding)
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Open")) {
                    openSpec(.issue(folderName: issue.id))
                }
                .contextMenu {
                    IssueContextMenuItems(
                        folderName: folder.lastPathComponent,
                        folderURL: folder,
                        projectURL: projectURL
                    )
                }
                .onTapGesture {
                    openSpec(.issue(folderName: issue.id))
                }
        }
    }

    private func cardAction(for value: Issue) -> WorkflowAction? {
        guard runStatus.liveRuns[value.folderName] == nil else { return nil }
        guard let action = WorkflowAction.available(status: value.status, type: value.type),
            !workflowCommandIsEmpty(action, value.type)
        else { return nil }
        return action
    }

    private func columnNeighbor(of value: Issue, offset: Int) -> String? {
        let items = kanban.groupedIssues[value.column] ?? []
        guard let index = items.firstIndex(where: { $0.id == value.folderName }) else {
            return nil
        }
        let neighbor = index + offset
        guard items.indices.contains(neighbor) else { return nil }
        return items[neighbor].id
    }

    @ViewBuilder
    private func validBody(_ value: Issue) -> some View {
        let isLocked = dirtyFolderName == value.folderName
        let payload = IssueDragPayload(folderName: value.folderName, currentStatus: value.status)
        // While this card is the active drag source, collapse it entirely:
        // frame to height 0, content clipped, opacity 0. The column's layout
        // then shows only the placeholder slot, never an empty source slot
        // beside it. View identity stays in the ForEach so the attached
        // DragGesture keeps firing throughout the drag.
        let cardOpacity: Double = isDragSource ? 0 : (isLocked ? 0.7 : 1.0)

        let availableAction = cardAction(for: value)

        IssueCardView(
            issue: value, padding: padding,
            isHighlighted: kanban.highlightedIssueID == value.folderName,
            liveRun: runStatus.liveRuns[value.folderName]?.state,
            openBlockers: value.blockedBy.isEmpty
                ? []
                : BlockerResolution.openBlockers(
                    blockedBy: value.blockedBy,
                    of: value.folderName,
                    index: BlockerResolution.index(kanban.issues)
                ),
            availableAction: availableAction,
            isActionDisabled: isLocked,
            onRunWorkflow: { action in
                runWorkflow(action, value.folderName, value.type)
            }
        )
        .opacity(cardOpacity)
        .frame(maxHeight: isDragSource ? 0 : nil)
        .clipped()
        .contentShape(Rectangle())
        .help(isLocked ? "Card has unsaved edits in the editor" : "")
        // Frame registry is the single source for both the drop-target resolver
        // and the drag-source frame; a parallel @State copy would double the
        // per-card layout pass.
        .reportCardFrame(folderName: value.folderName, registry: frameRegistry)
        // IssueCardView already calls .accessibilityElement(children: .combine);
        // .isButton is added here because the card-as-button trait belongs
        // to the gesture-bearing wrapper, not the rendering view.
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            // The combined card element swallows the inner workflow button.
            if let availableAction, !isLocked {
                Button("Run \(availableAction.label)") {
                    runWorkflow(availableAction, value.folderName, value.type)
                }
            }
            // Within-column reorder is otherwise gesture-only — these
            // actions are the keyboard/VoiceOver path to the same drop.
            if let above = columnNeighbor(of: value, offset: -1), !kanban.filter.isActive {
                Button("Move Up") {
                    guard !isLocked else { return }
                    kanban.dispatchDrop(
                        payload,
                        to: .aboveCard(folderName: above, column: value.column),
                        projectURL: projectURL)
                }
            }
            if let below = columnNeighbor(of: value, offset: 1), !kanban.filter.isActive {
                Button("Move Down") {
                    guard !isLocked else { return }
                    kanban.dispatchDrop(
                        payload,
                        to: .belowCard(folderName: below, column: value.column),
                        projectURL: projectURL)
                }
            }
            ForEach(IssueColumn.allCases.filter { $0 != value.column }, id: \.self) { target in
                Button("Move to \(target.name)") {
                    guard !isLocked else { return }
                    kanban.dispatchDrop(payload, to: .column(target), projectURL: projectURL)
                }
            }
        }
        .contextMenu {
            IssueContextMenuItems(
                folderName: value.folderName,
                folderURL: IssueLayout.issueFolder(
                    in: projectURL, folderName: value.folderName),
                projectURL: projectURL
            )
        }
        .modifier(
            CardInteraction(
                enabled: !isLocked,
                payload: payload,
                sourceIssue: value,
                sourceFrameProvider: { [frameRegistry] in
                    frameRegistry.rows[value.folderName] ?? .zero
                },
                onTap: { openSpec(.issue(folderName: value.folderName)) },
                onDispatch: { dispatchedPayload, target in
                    kanban.applyOptimisticDrop(
                        dispatchedPayload, to: target, projectURL: projectURL)
                }
            )
        )
    }
}

private struct CardInteraction: ViewModifier {
    let enabled: Bool
    let payload: IssueDragPayload
    let sourceIssue: Issue
    let sourceFrameProvider: () -> CGRect
    let onTap: () -> Void
    let onDispatch: (IssueDragPayload, ProjectKanbanModel.DropTarget) -> Void

    @Environment(KanbanDragController.self) private var controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if enabled {
            // ExclusiveGesture(Drag, Tap): drag wins as soon as movement
            // reaches minimumDistance (4pt) — tap is then excluded entirely.
            // A click without movement lets the tap fire and open the editor.
            // No NavigationLink: keeping the link's bridged button-tap alive
            // in parallel meant a drag-then-release-near-start would fire the
            // tap simultaneously and open the editor unexpectedly.
            content.gesture(buildDrag().exclusively(before: buildTap()))
        } else {
            content
        }
    }

    private func buildTap() -> some Gesture {
        TapGesture(count: 1).onEnded { onTap() }
    }

    private func buildDrag() -> some Gesture {
        // Pure DragGesture, no LongPressGesture. macOS Accessibility's
        // three-finger trackpad drag starts moving the cursor instantly on
        // touch — a LongPressGesture's "still for 150ms within 10pt" fails
        // every time on three-finger drag, killing the sequenced gesture
        // before the DragGesture can activate. minimumDistance: 4 is the
        // tap-vs-drag discriminator and works for mouse hold-drag,
        // accessibility three-finger drag, and trackpad drag-lock alike.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(KanbanCoordinateSpace.name))
            .onChanged { value in
                if !controller.isActive {
                    controller.startLift(
                        payload: KanbanDragItem(payload: payload, issue: sourceIssue),
                        sourceID: payload.folderName,
                        sourceFrame: sourceFrameProvider()
                    )
                }
                controller.updateCursor(
                    location: value.location, translation: value.translation)
            }
            .onEnded { _ in
                guard controller.isActive, let item = controller.payload else { return }
                if let resolved = controller.target {
                    let sourceFrame = controller.sourceFrame
                    let dropTranslation = CGSize(
                        width: resolved.insertionFrame.minX - sourceFrame.minX,
                        height: resolved.insertionFrame.minY - sourceFrame.minY
                    )
                    let dropDelayMs = reduceMotion ? 50 : 180
                    withAnimation(DragAnimations.drop(reduceMotion: reduceMotion)) {
                        controller.beginDrop(finalTranslation: dropTranslation)
                    }
                    let target = resolved.target
                    // Dispatch the optimistic update synchronously here so
                    // the issues array is at its final layout before the
                    // floating overlay clears. The controller owns the
                    // post-animation clear() via scheduleSettle, so we no
                    // longer fire and forget an unstructured Task — clear
                    // is cancellable through the controller's lifetime.
                    onDispatch(item.payload, target)
                    controller.scheduleSettle(after: .milliseconds(dropDelayMs))
                } else {
                    let cancelDelayMs = reduceMotion ? 50 : 300
                    withAnimation(DragAnimations.cancel(reduceMotion: reduceMotion)) {
                        controller.beginCancel()
                    }
                    controller.scheduleSettle(after: .milliseconds(cancelDelayMs))
                }
            }
    }
}

#Preview {
    NavigationStack {
        VStack(spacing: 8) {
            IssueCardSwitch(
                issue: .valid(
                    Issue(
                        id: 1,
                        folderName: "00001-walking-skeleton",
                        title: "Walking Skeleton",
                        type: .chore,
                        status: .done,
                        created: .distantPast,
                        updated: .distantPast,
                        branch: "issue/00001-walking-skeleton",
                        labels: ["bootstrap"]
                    )
                ),
                padding: 5,
                projectURL: URL(filePath: "/tmp/sample")
            )
            IssueCardSwitch(
                issue: .invalid(
                    folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken-stuff"),
                    error: .invalidEnumValue(field: "status", value: "aproved")
                ),
                padding: 5,
                projectURL: URL(filePath: "/tmp/sample")
            )
        }
        .padding()
        .frame(width: 260)
    }
    .environment(ProjectKanbanModel())
    .environment(KanbanDragController())
    .environment(RunStatusModel())
}
