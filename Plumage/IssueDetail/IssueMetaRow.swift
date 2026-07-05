import SwiftUI

struct IssueMetaRow: View {
    let status: IssueStatus
    let type: IssueType
    let availableTypes: [IssueType]
    let labels: [String]
    let existingLabels: [String]
    let dates: Dates?
    let onSelectStatus: (IssueStatus) -> Void
    let onSelectType: (IssueType) -> Void
    let onAddLabel: (String) -> Void
    let onRemoveLabel: (String) -> Void
    let isDisabled: Bool

    struct Dates: Equatable {
        let created: Date
        let updated: Date
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            statusMenu
                .disabled(isDisabled)
            typeMenu
                .disabled(isDisabled)
            Rectangle()
                .fill(.quaternary)
                .frame(width: 1)
                .frame(maxHeight: 16)
                .padding(.horizontal, 2)
                .accessibilityHidden(true)
            LabelChipEditor(
                labels: labels,
                existingLabels: existingLabels,
                onAdd: onAddLabel,
                onRemove: onRemoveLabel
            )
            .disabled(isDisabled)
            Spacer(minLength: 0)
            if let dates {
                timestampsView(dates)
            }
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(IssueStatus.allCases, id: \.self) { entry in
                Button {
                    onSelectStatus(entry)
                } label: {
                    HStack {
                        Text(entry.label)
                        if entry == status {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            IssueStatusPill(status: status)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Status: \(status.label)")
        .accessibilityHint("Choose a new status")
    }

    // The current type always renders, even after being deleted from the
    // catalog — otherwise the menu couldn't show the checkmark for it.
    private var menuTypes: [IssueType] {
        availableTypes.contains(type) ? availableTypes : [type] + availableTypes
    }

    private var typeMenu: some View {
        Menu {
            ForEach(menuTypes, id: \.self) { entry in
                Button {
                    onSelectType(entry)
                } label: {
                    HStack {
                        Text(entry.rawValue.capitalized)
                        if entry == type {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            IssueTypePill(type: type)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Type: \(type.rawValue.capitalized)")
        .accessibilityHint("Choose a new type")
    }

    @ViewBuilder
    private func timestampsView(_ dates: Dates) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
            Text("created \(Self.dateFormatter.string(from: dates.created))")
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.quaternary)
            Text("updated \(Self.dateFormatter.string(from: dates.updated))")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    // dateStyle/timeStyle, not a hardcoded pattern: "HH:mm" forced 24-hour
    // time regardless of the user's locale/12-hour preference.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    IssueMetaRow(
        status: .waitingForReview,
        type: .feature,
        availableTypes: IssueTypeCatalog.builtIn.types,
        labels: ["settings", "workflow"],
        existingLabels: ["ui", "backend", "perf"],
        dates: .init(created: Date(timeIntervalSinceNow: -3600), updated: Date()),
        onSelectStatus: { _ in },
        onSelectType: { _ in },
        onAddLabel: { _ in },
        onRemoveLabel: { _ in },
        isDisabled: false
    )
    .padding()
    .frame(width: 800)
}
