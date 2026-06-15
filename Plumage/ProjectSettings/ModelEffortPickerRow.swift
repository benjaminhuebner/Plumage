import SwiftUI

enum ModelEffortColumns {
    static let label: CGFloat = 160
    static let model: CGFloat = 160
    static let effort: CGFloat = 360
    static let spacing: CGFloat = 8
    static let pill: CGFloat = 136
    static let subRowIndent: CGFloat = 24
}

struct ModelEffortPickerRow: View {
    let label: String
    @Binding var modelChoice: ModelChoice
    @Binding var effortChoice: EffortLevel

    var body: some View {
        HStack(alignment: .center, spacing: ModelEffortColumns.spacing) {
            Text(label)
                .frame(width: ModelEffortColumns.label, alignment: .leading)
            ModelPickerCore(choice: $modelChoice)
                .frame(width: ModelEffortColumns.model, alignment: .leading)
            EffortSlider(
                choice: $effortChoice,
                stops: modelChoice.supportedEfforts,
                accessibilityLabel: "\(label) effort"
            )
            .frame(width: ModelEffortColumns.effort, alignment: .leading)
            Spacer(minLength: 0)
        }
    }
}

struct WorkflowModelEffortPickerRow: View {
    let slot: ModelSlot
    let model: ProjectSettingsModel

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: ModelEffortColumns.spacing) {
                disclosure
                ModelPickerCore(
                    choice: model.modelBinding(for: slot),
                    mixed: model.isWorkflowMixed(slot)
                )
                .frame(width: ModelEffortColumns.model, alignment: .leading)
                EffortSlider(
                    choice: model.effortBinding(for: slot),
                    stops: model.model(for: slot).supportedEfforts,
                    mixed: model.isWorkflowEffortMixed(slot),
                    accessibilityLabel: "\(slot.label) effort"
                )
                .frame(width: ModelEffortColumns.effort, alignment: .leading)
                Spacer(minLength: 0)
            }
            if expanded {
                ForEach(IssueType.allCases, id: \.self) { type in
                    let typeModel = model.workflowModelBinding(for: slot, type: type)
                    HStack(alignment: .center, spacing: ModelEffortColumns.spacing) {
                        IssueTypePill(type: type)
                            .frame(width: ModelEffortColumns.pill, alignment: .leading)
                            .padding(.leading, ModelEffortColumns.subRowIndent)
                        ModelPickerCore(choice: typeModel)
                            .frame(width: ModelEffortColumns.model, alignment: .leading)
                        EffortSlider(
                            choice: model.workflowEffortBinding(for: slot, type: type),
                            stops: typeModel.wrappedValue.supportedEfforts,
                            accessibilityLabel: "\(type.rawValue.capitalized) effort"
                        )
                        .frame(width: ModelEffortColumns.effort, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var disclosure: some View {
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
        .frame(width: ModelEffortColumns.label, alignment: .leading)
        .accessibilityLabel(
            "\(slot.label), \(expanded ? "collapse" : "expand") per-type models and efforts"
        )
    }
}
