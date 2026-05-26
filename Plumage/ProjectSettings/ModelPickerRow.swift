import SwiftUI

struct ModelPickerRow: View {
    let label: String
    @Binding var choice: ModelChoice

    // The picker exposes only concrete model aliases — `.default` is an
    // internal "no --model flag" sentinel that the user never sees. If a
    // legacy config persisted `.default` we still tag it so SwiftUI doesn't
    // crash on a missing tag at update; the menu just falls back to the
    // closest concrete option once the user touches it.
    static let pickerOptions: [ModelChoice] = [.opus, .sonnet, .haiku, .opusPlan]

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 160, alignment: .leading)
            Picker("", selection: $choice) {
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
}
