import SwiftUI

struct IssueCardSwitch: View {
    let issue: DiscoveredIssue
    let padding: Int
    let projectURL: URL
    var isDragSource: Bool = false

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(KanbanDragController.self) private var kanbanDrag
    @FocusedValue(\.specEditorDirtyFolderName) private var dirtyFolderName: String?
    @State private var sourceFrameInKanban: CGRect = .zero

    var body: some View {
        switch issue {
        case .valid(let value):
            validBody(value)
        case .invalid(let folder, let error):
            NavigationLink(value: SpecRoute.spec(folderName: issue.id)) {
                InvalidIssueCardView(folder: folder, error: error, padding: padding)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func validBody(_ value: Issue) -> some View {
        let isLocked = dirtyFolderName == value.folderName
        let payload = IssueDragPayload(folderName: value.folderName, currentStatus: value.status)
        // While this is the active drag source, fade the in-place card to zero
        // opacity. The card stays in the layout (slot remains visible as empty
        // space) so its IssueCardSwitch view identity persists — the attached
        // long-press+drag gesture continues to fire onChanged. Removing the
        // view from the column ForEach would tear the gesture down mid-drag.
        let cardOpacity: Double = isDragSource ? 0 : (isLocked ? 0.7 : 1.0)

        NavigationLink(value: SpecRoute.spec(folderName: value.folderName)) {
            IssueCardView(issue: value, padding: padding)
                .opacity(cardOpacity)
        }
        .buttonStyle(.plain)
        .help(isLocked ? "Card has unsaved edits in the editor" : "")
        .reportCardFrame(folderName: value.folderName)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(KanbanCoordinateSpace.name))
        } action: { frame in
            sourceFrameInKanban = frame
        }
        .accessibilityActions {
            ForEach(IssueColumn.allCases.filter { $0 != value.column }, id: \.self) { target in
                Button("Move to \(target.name)") {
                    guard !isLocked else { return }
                    kanban.dispatchDrop(payload, to: .column(target), projectURL: projectURL)
                }
            }
        }
        .modifier(
            ConditionalDragGesture(
                enabled: !isLocked,
                payload: payload,
                sourceFrameProvider: { sourceFrameInKanban },
                onDispatch: { dispatchedPayload, target in
                    kanban.dispatchDrop(dispatchedPayload, to: target, projectURL: projectURL)
                }
            )
        )
    }
}

private struct ConditionalDragGesture: ViewModifier {
    let enabled: Bool
    let payload: IssueDragPayload
    let sourceFrameProvider: () -> CGRect
    let onDispatch: (IssueDragPayload, ProjectKanbanModel.DropTarget) -> Void

    @Environment(KanbanDragController.self) private var controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if enabled {
            content.simultaneousGesture(buildGesture())
        } else {
            content
        }
    }

    private func buildGesture() -> some Gesture {
        let lift = LongPressGesture(minimumDuration: 0.15)
        let drag = DragGesture(coordinateSpace: .named(KanbanCoordinateSpace.name))
        return lift.sequenced(before: drag)
            .onChanged { value in
                switch value {
                case .first(true):
                    let frame = sourceFrameProvider()
                    withAnimation(KanbanAnimations.lift(reduceMotion: reduceMotion)) {
                        controller.startLift(
                            payload: payload,
                            sourceFolderName: payload.folderName,
                            sourceFrame: frame
                        )
                    }
                case .second(true, let dragValue?):
                    controller.updateCursor(
                        location: dragValue.location,
                        translation: dragValue.translation
                    )
                default:
                    break
                }
            }
            .onEnded { _ in
                guard controller.isActive, let payload = controller.payload else { return }
                if let resolved = controller.target {
                    let sourceFrame = controller.sourceFrame
                    let dropTranslation = CGSize(
                        width: resolved.insertionFrame.minX - sourceFrame.minX,
                        height: resolved.insertionFrame.minY - sourceFrame.minY
                    )
                    let dropDelayMs = reduceMotion ? 50 : 180
                    withAnimation(KanbanAnimations.drop(reduceMotion: reduceMotion)) {
                        controller.beginDrop(finalTranslation: dropTranslation)
                    }
                    let target = resolved.target
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(dropDelayMs))
                        onDispatch(payload, target)
                        controller.clear()
                    }
                } else {
                    let cancelDelayMs = reduceMotion ? 50 : 300
                    withAnimation(KanbanAnimations.cancel(reduceMotion: reduceMotion)) {
                        controller.beginCancel()
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(cancelDelayMs))
                        controller.clear()
                    }
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
                        labels: ["bootstrap"],
                        model: nil
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
}
