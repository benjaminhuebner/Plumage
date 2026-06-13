import SwiftUI

struct EffortPickerRow: View {
    let label: String
    @Binding var choice: EffortLevel

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 160, alignment: .leading)
            EffortPickerCore(choice: $choice)
            Spacer(minLength: 0)
        }
    }
}

struct EffortPickerCore: View {
    @Binding var choice: EffortLevel
    var mixed: Bool = false

    static let presets: [EffortLevel] = [.default, .low, .medium, .high, .xhigh, .max]

    private enum Selection: Hashable {
        case preset(EffortLevel)
        case mixed
    }

    var body: some View {
        Picker("", selection: selectionBinding) {
            ForEach(Self.presets, id: \.self) { option in
                Text(option.displayName).tag(Selection.preset(option))
            }
            if mixed {
                Text("Mixed").tag(Selection.mixed)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220, alignment: .leading)
    }

    private var selectionBinding: Binding<Selection> {
        Binding(
            get: {
                if mixed { return .mixed }
                return .preset(choice)
            },
            set: { newValue in
                switch newValue {
                case .preset(let preset):
                    choice = preset
                case .mixed:
                    // Display-only row so the menu can show "Mixed"; never applied.
                    break
                }
            }
        )
    }
}
