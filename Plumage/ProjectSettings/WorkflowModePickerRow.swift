import SwiftUI

struct WorkflowModePickerRow: View {
    let label: String
    @Binding var mode: PermissionMode?
    let fallback: PermissionMode

    var body: some View {
        HStack {
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 160, alignment: .leading)
            Picker("", selection: modeBinding) {
                ForEach(PermissionMode.allCases, id: \.self) { pm in
                    if pm == fallback {
                        // The action's built-in default. Tagged nil so picking
                        // it clears the override; pre-selected when no override
                        // is set.
                        Text("\(pm.displayName) (Default)")
                            .tag(Optional<PermissionMode>.none)
                    } else {
                        Text(pm.displayName).tag(Optional(pm))
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
            .accessibilityLabel("\(label) permission mode")
            Spacer(minLength: 0)
        }
    }

    // Picker selection is PermissionMode? — nil means "no override, use the
    // built-in default". An explicit on-disk override equal to the fallback
    // is coerced to nil for display so the picker shows "(Default)" instead of
    // a blank selection (the fallback value has no Optional(pm)-tagged row).
    private var modeBinding: Binding<PermissionMode?> {
        Binding(
            get: { mode == fallback ? nil : mode },
            set: { mode = $0 }
        )
    }
}
