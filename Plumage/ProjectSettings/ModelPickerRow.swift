import SwiftUI

struct ModelPickerRow: View {
    let label: String
    @Binding var choice: ModelChoice

    static let presets: [ModelChoice] = [.default, .fable, .opus, .sonnet, .haiku]

    private enum Selection: Hashable {
        case preset(ModelChoice)
        case custom
    }

    // "Custom…" can be picked before any text is committed; `choice` keeps its
    // previous value until then, so the selection needs its own state.
    @State private var customSelected = false
    @State private var customText = ""
    @FocusState private var customFieldFocused: Bool

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 160, alignment: .leading)
            Picker("", selection: selectionBinding) {
                ForEach(Self.presets, id: \.self) { option in
                    Text(option.displayName).tag(Selection.preset(option))
                }
                Text(customRowLabel)
                    .tag(Selection.custom)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
            if showsCustomField {
                TextField("Model name or alias", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .focused($customFieldFocused)
                    .onSubmit(commitCustomText)
                    .onChange(of: customFieldFocused) { _, focused in
                        if !focused { commitCustomText() }
                    }
            }
            Spacer(minLength: 0)
        }
        .onAppear(perform: syncFromChoice)
        .onChange(of: choice) { syncFromChoice() }
    }

    private var showsCustomField: Bool {
        if customSelected { return true }
        if case .custom = choice { return true }
        return false
    }

    private var customRowLabel: String {
        if case .custom(let value) = choice { return value }
        return "Custom…"
    }

    private var selectionBinding: Binding<Selection> {
        Binding(
            get: {
                if customSelected { return .custom }
                if case .custom = choice { return .custom }
                return .preset(choice)
            },
            set: { newValue in
                switch newValue {
                case .preset(let preset):
                    customSelected = false
                    customText = ""
                    choice = preset
                case .custom:
                    customSelected = true
                    customFieldFocused = true
                }
            }
        )
    }

    // The storage mapping collapses known aliases to their picker row and maps
    // empty text to Default — no empty `--model` value ever reaches config.json.
    private func commitCustomText() {
        let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        choice = ModelChoice(storageValue: trimmed)
        syncFromChoice()
    }

    private func syncFromChoice() {
        if case .custom(let value) = choice {
            customSelected = true
            customText = value
        } else {
            customSelected = false
            customText = ""
        }
    }
}
