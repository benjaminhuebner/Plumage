import SwiftUI

struct ModelPickerRow: View {
    let label: String
    @Binding var choice: ModelChoice

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 160, alignment: .leading)
            Picker("", selection: $choice) {
                ForEach(ModelChoice.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
            Spacer(minLength: 0)
        }
    }
}
