import SwiftUI

struct IssueCardSwitch: View {
    let issue: DiscoveredIssue
    let padding: Int
    let projectURL: URL

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

        NavigationLink(value: SpecRoute.spec(folderName: value.folderName)) {
            IssueCardView(issue: value, padding: padding)
                .opacity(isLocked ? 0.7 : 1.0)
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
                onDispatch: { target in
                    kanban.dispatchDrop(payload, to: target, projectURL: projectURL)
                }
            )
        )
    }
}

private struct ConditionalDragGesture: ViewModifier {
    let enabled: Bool
    let payload: IssueDragPayload
    let sourceFrameProvider: () -> CGRect
    let onDispatch: (ProjectKanbanModel.DropTarget) -> Void

    @Environment(KanbanDragController.self) private var controller

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
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
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
                if let resolved = controller.state?.target {
                    onDispatch(resolved.target)
                }
                controller.clear()
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
