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
                        scrollPosition: columnScrollBinding(for: column)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollPosition($autoScroll.horizontalScroll)
        .scrollDisabled(kanbanDrag.isActive)
        .coordinateSpace(name: KanbanCoordinateSpace.name)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            kanbanFrame = CGRect(origin: .zero, size: size)
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
        // .onKeyPress(.escape) does not reliably fire while a mouse drag holds
        // the responder chain; a local NSEvent monitor catches the keystroke
        // regardless of focus and lets us cancel the drag mid-gesture.
        .task(id: kanbanDrag.isActive) {
            await monitorEscape()
        }
    }

    private func columnScrollBinding(for column: IssueColumn) -> Binding<ScrollPosition> {
        Binding(
            get: { autoScroll.columnPosition(column) },
            set: { autoScroll.setColumnPosition(column, to: $0) }
        )
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 50 : 300))
            kanbanDrag.clear()
        }
    }

    private func monitorEscape() async {
        guard kanbanDrag.isActive else { return }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
        while !Task.isCancelled, kanbanDrag.isActive {
            try? await Task.sleep(for: .milliseconds(100))
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
// needs (translation, sourceFrame, status, sourceFolderName). KanbanView's body
// no longer re-evaluates on every cursor frame.
private struct FloatingDragCard: View {
    let padding: Int
    @Environment(KanbanDragController.self) private var kanbanDrag
    @Environment(ProjectKanbanModel.self) private var kanban

    var body: some View {
        if kanbanDrag.isActive, let folderName = kanbanDrag.sourceFolderName,
            let issue = lookup(folderName: folderName)
        {
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

    private func lookup(folderName: String) -> Issue? {
        for item in kanban.issues {
            if case .valid(let issue) = item, issue.folderName == folderName {
                return issue
            }
        }
        return nil
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
