import AppKit
import SwiftUI

struct KanbanView: View {
    let grouped: [IssueColumn: [DiscoveredIssue]]
    let padding: Int
    let projectURL: URL

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(\.scenePhase) private var scenePhase
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var columnFrames: [IssueColumn: CGRect] = [:]
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
        .scrollDisabled(kanbanDrag.state != nil)
        .coordinateSpace(name: KanbanCoordinateSpace.name)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            kanbanFrame = CGRect(origin: .zero, size: size)
        }
        .overlay(alignment: .topLeading) {
            floatingDragCard
        }
        .environment(kanbanDrag)
        .onPreferenceChange(CardFramesPreferenceKey.self) { frames in
            cardFrames = frames
        }
        .onPreferenceChange(ColumnFramesPreferenceKey.self) { frames in
            columnFrames = frames
        }
        .onChange(of: kanbanDrag.state?.cursorLocation) { _, _ in
            updateResolvedTarget()
            updateAutoScroll()
        }
        .onChange(of: kanbanDrag.state != nil) { _, active in
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
        .task(id: kanbanDrag.state != nil) {
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
        guard let drag = kanbanDrag.state else {
            autoScroll.stop()
            return
        }
        autoScroll.update(
            active: drag.status == .dragging || drag.status == .lifting,
            cursor: drag.cursorLocation,
            kanbanFrame: kanbanFrame,
            columnFrames: columnFrames
        )
    }

    @ViewBuilder
    private var floatingDragCard: some View {
        if let drag = kanbanDrag.state, let issue = floatingIssue(drag.sourceFolderName) {
            IssueCardView(issue: issue, padding: padding)
                .frame(width: drag.sourceFrame.width, height: drag.sourceFrame.height)
                .scaleEffect(drag.status == .cancelling ? 1.0 : 1.04)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                .offset(
                    x: drag.sourceFrame.minX + drag.translation.width,
                    y: drag.sourceFrame.minY + drag.translation.height
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func floatingIssue(_ folderName: String) -> Issue? {
        for item in kanban.issues {
            if case .valid(let issue) = item, issue.folderName == folderName {
                return issue
            }
        }
        return nil
    }

    private func cancelDrag() {
        guard kanbanDrag.state != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            kanbanDrag.beginCancel()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            kanbanDrag.clear()
        }
    }

    private func monitorEscape() async {
        guard kanbanDrag.state != nil else { return }
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
        while !Task.isCancelled, kanbanDrag.state != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func updateResolvedTarget() {
        guard let drag = kanbanDrag.state else { return }
        let resolved = resolveDropTarget(
            cursor: drag.cursorLocation,
            cardFrames: cardFrames,
            columnFrames: columnFrames,
            sortedIssues: grouped,
            sourceFolderName: drag.sourceFolderName
        )
        if drag.target != resolved {
            withAnimation(.smooth(duration: 0.18)) {
                kanbanDrag.setTarget(resolved)
            }
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
