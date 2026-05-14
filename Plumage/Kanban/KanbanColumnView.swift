import SwiftUI

struct KanbanColumnView: View {
    let column: IssueColumn
    let issues: [DiscoveredIssue]
    let padding: Int
    let projectURL: URL

    @FocusedValue(\.newIssueSheetIsPresented) private var newIssueSheetIsPresented
    @Environment(ProjectKanbanModel.self) private var kanban
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .padding(.horizontal, 4)

            if issues.isEmpty {
                Text("No issues")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(issues) { item in
                            IssueCardSwitch(
                                issue: item, padding: padding, projectURL: projectURL)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .frame(minWidth: 240, maxWidth: 280, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .reportColumnFrame(column: column)
        .dropDestination(for: IssueDragPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            kanban.dispatchDrop(payload, to: .column(column), projectURL: projectURL)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isDropTargeted ? 0.6 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        )
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
}
