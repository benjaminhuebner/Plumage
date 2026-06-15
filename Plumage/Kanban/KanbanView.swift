import SwiftUI

struct KanbanView: View {
    let grouped: [IssueColumn: [DiscoveredIssue]]
    let padding: Int
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames = KanbanFrameRegistry()
    @State private var kanbanFrame: CGRect = .zero
    @State private var kanbanDrag = KanbanDragController()
    @State private var autoScroll = KanbanAutoScroll()
    // Source-filtered columns, computed once per lift instead of per cursor
    // move (resolveDropTarget fires on every drag frame). Invalidated on
    // drag end and on any grouped-snapshot change mid-drag.
    @State private var dragFilteredIssues: [IssueColumn: [DiscoveredIssue]]?

    var body: some View {
        @Bindable var autoScroll = autoScroll

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(IssueColumn.allCases) { column in
                    KanbanColumnView(
                        column: column,
                        issues: grouped[column] ?? [],
                        padding: padding,
                        projectURL: projectURL,
                        autoScroll: autoScroll
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollPosition($autoScroll.horizontalScroll)
        .scrollDisabled(kanbanDrag.isActive)
        .coordinateSpace(name: KanbanCoordinateSpace.name)
        // Read the rect in the same coordinate space the column and card
        // frames are recorded in, so auto-scroll edge math compares
        // apples-to-apples rather than relying on the modifier landing on
        // the ScrollView's own bounds.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(KanbanCoordinateSpace.name))
        } action: { frame in
            if !DragGeometry.framesNearlyEqual(kanbanFrame, frame) {
                kanbanFrame = frame
            }
        }
        .overlay(alignment: .topLeading) {
            FloatingDragOverlay(controller: kanbanDrag) { item in
                IssueCardView(issue: item.issue, padding: padding, isHighlighted: false)
            }
        }
        .environment(kanbanDrag)
        .environment(\.kanbanFrameRegistry, frames)
        .onChange(of: kanbanDrag.cursorLocation) { _, _ in
            updateResolvedTarget()
            updateAutoScroll()
        }
        .onChange(of: kanbanDrag.isActive) { _, active in
            if !active {
                autoScroll.stop()
                dragFilteredIssues = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                cancelDrag()
            }
        }
        .onChange(of: grouped) { _, newGrouped in
            // Drop stale card frames as soon as the issue list changes,
            // otherwise the registry accumulates entries for closed/deleted
            // issues across a long session and resolveDropTarget iterates
            // ghost rects.
            var live: Set<String> = []
            for items in newGrouped.values {
                for item in items {
                    live.insert(item.id)
                }
            }
            frames.pruneRows(keeping: live)
            dragFilteredIssues = nil
        }
        .task(id: kanbanDrag.isActive) {
            guard kanbanDrag.isActive else { return }
            await DragEscapeMonitor.run { cancelDrag() }
        }
    }

    private func updateAutoScroll() {
        guard kanbanDrag.isActive else {
            autoScroll.stop()
            return
        }
        let status = kanbanDrag.status
        autoScroll.update(
            active: status == .dragging || status == .lifting,
            cursor: kanbanDrag.cursorLocation,
            kanbanFrame: kanbanFrame,
            columnFrames: frames.containers
        )
    }

    private func cancelDrag() {
        guard kanbanDrag.isActive else { return }
        withAnimation(DragAnimations.cancel(reduceMotion: reduceMotion)) {
            kanbanDrag.beginCancel()
        }
        // Hand the post-animation clear to the controller so its lifetime
        // governs the cleanup, instead of a fire-and-forget Task that
        // outlives the view.
        kanbanDrag.scheduleSettle(after: .milliseconds(reduceMotion ? 50 : 300))
    }

    private func updateResolvedTarget() {
        guard kanbanDrag.isActive, let source = kanbanDrag.sourceID else { return }
        let filtered: [IssueColumn: [DiscoveredIssue]]
        if let cached = dragFilteredIssues {
            filtered = cached
        } else {
            filtered = grouped.mapValues { items in items.filter { $0.id != source } }
            dragFilteredIssues = filtered
        }
        let resolved = resolveDropTarget(
            cursor: kanbanDrag.cursorLocation,
            cardFrames: frames.rows,
            columnFrames: frames.containers,
            sortedIssues: filtered,
            sourceFolderName: source
        )
        guard kanbanDrag.target != resolved else { return }
        // Wrap the target change explicitly so only the placeholder-gap
        // transition animates. The `.animation(_, value:)` modifier on the
        // LazyVStack was animating EVERY layout change tied to the column
        // — including the source's insertion on drop, where the new row
        // would first appear at LazyVStack's default position and then
        // animate to its correct slot. By driving the animation from here
        // instead, only deliberate target changes during drag are smooth;
        // the drop itself snaps.
        withAnimation(DragAnimations.placeholder(reduceMotion: reduceMotion)) {
            kanbanDrag.setTarget(resolved)
        }
    }
}

private func kanbanPreviewIssues() -> [DiscoveredIssue] {
    [
        .valid(
            Issue(
                id: 1, folderName: "00001-walking-skeleton", title: "Walking Skeleton",
                type: .chore, status: .done, created: .distantPast, updated: .distantPast,
                branch: "issue/00001-walking-skeleton", labels: ["bootstrap"]
            )
        ),
        .valid(
            Issue(
                id: 2, folderName: "00002-config", title: "Project config",
                type: .feature, status: .waitingForReview, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00002-config", labels: ["feature", "v0.1"]
            )
        ),
        .valid(
            Issue(
                id: 3, folderName: "00003-list", title: "List view",
                type: .feature, status: .inProgress, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00003-list", labels: ["feature", "v0.1"]
            )
        ),
        .valid(
            Issue(
                id: 4, folderName: "00004-discovery", title: "Discovery",
                type: .feature, status: .approved, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00004-discovery", labels: ["feature", "v0.1"]
            )
        ),
        .valid(
            Issue(
                id: 5, folderName: "00005-kanban", title: "Kanban grouping",
                type: .feature, status: .draft, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00005-kanban", labels: ["feature", "v0.1"]
            )
        ),
        .invalid(
            folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken"),
            error: .invalidEnumValue(field: "status", value: "aproved")
        ),
    ]
}

#Preview {
    KanbanView(
        grouped: Dictionary(grouping: kanbanPreviewIssues(), by: \.column),
        padding: 5,
        projectURL: URL(filePath: "/tmp/sample")
    )
    .frame(width: 1100, height: 600)
}
