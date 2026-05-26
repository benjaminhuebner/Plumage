import SwiftUI

struct ModelPickerRow: View {
    let label: String
    @Binding var choice: ModelChoice
    // Concrete option shown in the picker when the bound `choice` is the
    // internal `.default` sentinel (legacy config with `"chat": "default"`
    // on disk). Without this, SwiftUI Picker would render a blank selection
    // because `.default` has no tagged row.
    let fallback: ModelChoice

    // The picker exposes only concrete model aliases — `.default` is an
    // internal "no --model flag" sentinel that the user never sees.
    static let pickerOptions: [ModelChoice] = [.opus, .sonnet, .haiku, .opusPlan]

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 160, alignment: .leading)
            Picker("", selection: pickerBinding) {
                ForEach(Self.pickerOptions, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    // Coerces a stored `.default` to the slot fallback for display so the
    // menu shows a concrete row instead of empty selection. Writes pass
    // through unchanged — the user's pick always lands on a concrete option.
    private var pickerBinding: Binding<ModelChoice> {
        Binding(
            get: { choice == .default ? fallback : choice },
            set: { choice = $0 }
        )
    }
}
