import SwiftUI

struct IssueDetailFormRows: View {
    let type: IssueType
    let status: IssueStatus
    // nil hides the Created/Updated row entirely (creating mode has no dates).
    let dates: Dates?
    let onSelectType: (IssueType) -> Void
    let onSelectStatus: (IssueStatus) -> Void
    let isDisabled: Bool

    struct Dates: Equatable {
        let created: Date
        let updated: Date
    }

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

            if let dates {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    pairedRow("Created") {
                        Text(Self.dateFormatter.string(from: dates.created))
                            .foregroundStyle(.secondary)
                    }
                    pairedRow("Updated") {
                        Text(Self.dateFormatter.string(from: dates.updated))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // Menu+Button avoids the Binding(get:set:) anti-pattern: a Picker with
    // a callback would need a new Binding per body eval; a Menu just reads
    // the current selection and dispatches via callback on tap.
    private var typeMenu: some View {
        Menu {
            ForEach(IssueType.allCases, id: \.self) { entry in
                Button {
                    onSelectType(entry)
                } label: {
                    Label {
                        Text(entry.rawValue.capitalized)
                    } icon: {
                        Circle().fill(entry.color)
                    }
                    if entry == type {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(type.color).frame(width: 10, height: 10)
                Text(type.rawValue.capitalized)
            }
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(IssueStatus.allCases, id: \.self) { entry in
                Button {
                    onSelectStatus(entry)
                } label: {
                    Label {
                        Text(entry.label)
                    } icon: {
                        Circle().fill(entry.indicatorColor)
                    }
                    if entry == status {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(status.indicatorColor).frame(width: 10, height: 10)
                Text(status.label)
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

    // Shared across all instances; the body always runs on the MainActor, so
    // the formatter's documented "not reentrant from multiple threads"
    // constraint does not apply here.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    IssueDetailFormRows(
        type: .feature,
        status: .inProgress,
        dates: .init(created: Date(), updated: Date()),
        onSelectType: { _ in },
        onSelectStatus: { _ in },
        isDisabled: false
    )
    .padding()
    .frame(width: 700)
}
