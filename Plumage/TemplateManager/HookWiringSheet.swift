import SwiftUI

// Event picker (+ optional matcher) for wiring a hook into settings.json. Used both
// when a hook is first added/imported and later via "Edit wiring…", pre-filled from
// the existing wiring. Cancelling leaves the hook unwired (the row flags it).
struct HookWiringSheet: View {
    let hookName: String
    let initial: HookWiring?
    let onSave: (HookEvent, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var event: HookEvent
    @State private var matcher: String

    init(hookName: String, initial: HookWiring?, onSave: @escaping (HookEvent, String?) -> Void) {
        self.hookName = hookName
        self.initial = initial
        self.onSave = onSave
        _event = State(initialValue: initial?.event ?? .preToolUse)
        _matcher = State(initialValue: initial?.matcher ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wire Hook “\(hookName)”")
                .font(.headline)
            Picker("Event", selection: $event) {
                ForEach(HookEvent.allCases, id: \.self) { event in
                    Text(event.displayName).tag(event)
                }
            }
            if event.supportsMatcher {
                TextField("Matcher (e.g. Edit|Write)", text: $matcher)
                    .textFieldStyle(.roundedBorder)
            }
            Text("The hook runs on this event in every new project that scaffolds it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    let trimmed = matcher.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(event, trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
