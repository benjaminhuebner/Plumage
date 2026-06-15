import SwiftUI

struct WorkflowEffortPickerRow: View {
    let slot: ModelSlot
    let model: ProjectSettingsModel

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text(slot.label)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 160, alignment: .leading)
                .accessibilityLabel(
                    "\(slot.label), \(expanded ? "collapse" : "expand") per-type efforts"
                )
                EffortPickerCore(
                    choice: model.effortBinding(for: slot),
                    mixed: model.isWorkflowEffortMixed(slot),
                    accessibilityLabel: "\(slot.label) effort"
                )
                Spacer(minLength: 0)
            }
            if expanded {
                ForEach(IssueType.allCases, id: \.self) { type in
                    HStack {
                        IssueTypePill(type: type)
                            .frame(width: 136, alignment: .leading)
                            .padding(.leading, 24)
                        EffortPickerCore(
                            choice: model.workflowEffortBinding(for: slot, type: type),
                            accessibilityLabel: "\(type.rawValue.capitalized) effort"
                        )
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}
