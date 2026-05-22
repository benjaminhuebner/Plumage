import AppKit
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
            let raw = proxy.frame(in: .named(KanbanCoordinateSpace.name))
            return CGRect(
                x: raw.origin.x.rounded(.down), y: raw.origin.y.rounded(.down),
                width: raw.size.width.rounded(.down), height: raw.size.height.rounded(.down))
        } action: { frame in
            if kanbanFrame != frame {
                kanbanFrame = frame
            }
        }
        .overlay(alignment: .topLeading) {
            FloatingDragCard(padding: padding)
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
            frames.pruneCards(keeping: live)
        }
        // .onKeyPress(.escape) does not reliably fire while a mouse drag holds
        // the responder chain; a local NSEvent monitor catches the keystroke
        // regardless of focus and lets us cancel the drag mid-gesture.
        .task(id: kanbanDrag.isActive) {
            await monitorEscape()
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
            columnFrames: frames.columns
        )
    }

    private func cancelDrag() {
        guard kanbanDrag.isActive else { return }
        withAnimation(KanbanAnimations.cancel(reduceMotion: reduceMotion)) {
            kanbanDrag.beginCancel()
        }
        // Hand the post-animation clear to the controller so its lifetime
        // governs the cleanup, instead of a fire-and-forget Task that
        // outlives the view.
        kanbanDrag.scheduleSettle(after: .milliseconds(reduceMotion ? 50 : 300))
    }

    private func monitorEscape() async {
        guard kanbanDrag.isActive else { return }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @Sendable event in
            if event.keyCode == 53 {
                Task { @MainActor in cancelDrag() }
                return nil
            }
            return event
        }
        defer {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        // Suspend until .task(id:) cancels this task — the cancellation
        // triggers when kanbanDrag.isActive flips. Previously a 50ms poll
        // loop did the same job, but left a ~50ms trailing window where the
        // monitor still listened past drag-end. Cancellation runs the
        // defer-block above and removes the monitor synchronously.
        while !Task.isCancelled {
            do {
                // Long suspend with no work to do: .task(id:) will throw
                // CancellationError into Task.sleep when isActive flips, the
                // catch breaks out, and defer fires immediately.
                try await Task.sleep(for: .seconds(60))
            } catch {
                break
            }
        }
    }

    private func updateResolvedTarget() {
        guard kanbanDrag.isActive, let source = kanbanDrag.sourceFolderName else { return }
        let resolved = resolveDropTarget(
            cursor: kanbanDrag.cursorLocation,
            cardFrames: frames.cards,
            columnFrames: frames.columns,
            sortedIssues: grouped,
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
        withAnimation(KanbanAnimations.placeholder(reduceMotion: reduceMotion)) {
            kanbanDrag.setTarget(resolved)
        }
    }
}

// Hoisted into its own view so it observes only the controller properties it
// needs (translation, sourceFrame, status, sourceFolderName, sourceIssue).
// KanbanView's body no longer re-evaluates on every cursor frame, and the
// floating card no longer depends on the full ProjectKanbanModel.issues
// array — the source issue is cached at lift time on the controller.
private struct FloatingDragCard: View {
    let padding: Int
    @Environment(KanbanDragController.self) private var kanbanDrag

    var body: some View {
        if kanbanDrag.isActive, let issue = kanbanDrag.sourceIssue {
            let frame = kanbanDrag.sourceFrame
            let translation = kanbanDrag.translation
            IssueCardView(issue: issue, padding: padding)
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(kanbanDrag.status == .cancelling ? 1.0 : 1.04)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                .offset(
                    x: frame.minX + translation.width,
                    y: frame.minY + translation.height
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private func kanbanPreviewIssues() -> [DiscoveredIssue] {
    [
        .valid(
            Issue(
                id: 1, folderName: "00001-walking-skeleton", title: "Walking Skeleton",
                type: .chore, status: .done, created: .distantPast, updated: .distantPast,
                branch: "issue/00001-walking-skeleton", labels: ["bootstrap"], model: nil
            )
        ),
        .valid(
            Issue(
                id: 2, folderName: "00002-config", title: "Project config",
                type: .feature, status: .waitingForReview, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00002-config", labels: ["feature", "v0.1"], model: nil
            )
        ),
        .valid(
            Issue(
                id: 3, folderName: "00003-list", title: "List view",
                type: .feature, status: .inProgress, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00003-list", labels: ["feature", "v0.1"], model: nil
            )
        ),
        .valid(
            Issue(
                id: 4, folderName: "00004-discovery", title: "Discovery",
                type: .feature, status: .approved, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00004-discovery", labels: ["feature", "v0.1"], model: nil
            )
        ),
        .valid(
            Issue(
                id: 5, folderName: "00005-kanban", title: "Kanban grouping",
                type: .feature, status: .draft, created: .distantPast,
                updated: .distantPast,
                branch: "issue/00005-kanban", labels: ["feature", "v0.1"], model: nil
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
