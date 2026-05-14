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
                    Picker("", selection: typeBinding) {
                        ForEach(IssueType.allCases, id: \.self) { type in
                            HStack {
                                Circle().fill(type.color).frame(width: 10, height: 10)
                                Text(type.rawValue.capitalized)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(isDisabled)
                }
                pairedRow("Status") {
                    Picker("", selection: statusBinding) {
                        ForEach(IssueStatus.allCases, id: \.self) { status in
                            HStack {
                                Circle().fill(status.indicatorColor).frame(width: 10, height: 10)
                                Text(status.label)
                            }
                            .tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(isDisabled)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 24) {
                pairedRow("Created") {
                    Text(Self.formatted(issue.created))
                        .foregroundStyle(.secondary)
                }
                pairedRow("Updated") {
                    Text(Self.formatted(issue.updated))
                        .foregroundStyle(.secondary)
                }
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

    private var typeBinding: Binding<IssueType> {
        Binding(
            get: { issue.type },
            set: { onSelectType($0) }
        )
    }

    private var statusBinding: Binding<IssueStatus> {
        Binding(
            get: { issue.status },
            set: { onSelectStatus($0) }
        )
    }

    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
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
