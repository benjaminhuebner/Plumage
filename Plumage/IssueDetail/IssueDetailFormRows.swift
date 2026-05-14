import SwiftUI

struct IssueDetailFormRows: View {
    let issue: Issue
    let onSelectType: (IssueType) -> Void
    let onSelectStatus: (IssueStatus) -> Void
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                pairedRow("Type") {
                    typeMenu
                        .disabled(isDisabled)
                }
                pairedRow("Status") {
                    statusMenu
                        .disabled(isDisabled)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 24) {
                pairedRow("Created") {
                    Text(Self.dateFormatter.string(from: issue.created))
                        .foregroundStyle(.secondary)
                }
                pairedRow("Updated") {
                    Text(Self.dateFormatter.string(from: issue.updated))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // Menu+Button avoids the Binding(get:set:) anti-pattern: a Picker with
    // a callback would need a new Binding per body eval; a Menu just reads
    // issue.type/status directly and dispatches via callback on tap.
    private var typeMenu: some View {
        Menu {
            ForEach(IssueType.allCases, id: \.self) { type in
                Button {
                    onSelectType(type)
                } label: {
                    Label {
                        Text(type.rawValue.capitalized)
                    } icon: {
                        Circle().fill(type.color)
                    }
                    if type == issue.type {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(issue.type.color).frame(width: 10, height: 10)
                Text(issue.type.rawValue.capitalized)
            }
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(IssueStatus.allCases, id: \.self) { status in
                Button {
                    onSelectStatus(status)
                } label: {
                    Label {
                        Text(status.label)
                    } icon: {
                        Circle().fill(status.indicatorColor)
                    }
                    if status == issue.status {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(issue.status.indicatorColor).frame(width: 10, height: 10)
                Text(issue.status.label)
            }
        }
    }

    @ViewBuilder
    private func pairedRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
                .font(.callout)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    IssueDetailFormRows(
        issue: Issue(
            id: 16,
            folderName: "00016-better-issue-details",
            title: "Better Issue-Details View",
            type: .feature,
            status: .inProgress,
            created: Date(),
            updated: Date(),
            branch: "issue/00016-better-issue-details",
            labels: ["ui", "ux"],
            model: nil
        ),
        onSelectType: { _ in },
        onSelectStatus: { _ in },
        isDisabled: false
    )
    .padding()
    .frame(width: 700)
}
