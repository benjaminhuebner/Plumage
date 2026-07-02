import SwiftUI

struct DoneWhenChecklist: View {
    let criteria: [DoneWhenCriterion]
    let isDisabled: Bool
    let binding: (Int) -> Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checklist")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Done when")
                        .font(.headline)
                    Text("\(checkedCount)/\(criteria.count) criteria checked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(criteria.enumerated()), id: \.offset) { index, criterion in
                    Toggle(isOn: binding(index)) {
                        Text(attributed(criterion.text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(isDisabled)
                    .accessibilityLabel("Done-when criterion \(index + 1)")
                }
            }
        }
    }

    private var checkedCount: Int {
        criteria.count { $0.isChecked }
    }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

#Preview("Checklist") {
    DoneWhenChecklist(
        criteria: [
            DoneWhenCriterion(text: "A fresh run produces `evidence.json`", isChecked: true),
            DoneWhenCriterion(text: "The staleness hint appears after a manual commit", isChecked: false),
            DoneWhenCriterion(text: "Merge is never blocked by evidence", isChecked: false),
        ],
        isDisabled: false,
        binding: { _ in .constant(false) }
    )
    .padding()
    .frame(width: 600)
}

#Preview("Disabled by conflict") {
    DoneWhenChecklist(
        criteria: [
            DoneWhenCriterion(text: "First criterion", isChecked: false)
        ],
        isDisabled: true,
        binding: { _ in .constant(false) }
    )
    .padding()
    .frame(width: 600)
}
