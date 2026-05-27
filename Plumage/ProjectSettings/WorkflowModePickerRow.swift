import SwiftUI

struct WorkflowModePickerRow: View {
    let label: String
    @Binding var mode: PermissionMode?
    let fallback: PermissionMode

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 160, alignment: .leading)
            Picker("", selection: modeBinding) {
                Text("Built-in (\(fallback.displayName))")
                    .tag(Optional<PermissionMode>.none)
                Divider()
                ForEach(PermissionMode.allCases, id: \.self) { pm in
                    Text(pm.displayName).tag(Optional(pm))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    // Picker selection is PermissionMode? — nil means "use built-in".
    private var modeBinding: Binding<PermissionMode?> {
        Binding(get: { mode }, set: { mode = $0 })
    }
}
