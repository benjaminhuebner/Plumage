import SwiftUI

struct SchemePicker: View {
    @Bindable var model: XcodeRunModel
    let onReload: () -> Void

    var body: some View {
        Menu {
            ForEach(model.schemes, id: \.self) { scheme in
                Button {
                    Task { await model.selectScheme(scheme) }
                } label: {
                    if scheme == model.selectedScheme {
                        Label(scheme, systemImage: "checkmark")
                    } else {
                        Text(scheme)
                    }
                }
            }
            if !model.schemes.isEmpty { Divider() }
            Button {
                onReload()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "hammer")
                Text(model.selectedScheme ?? "No scheme")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
        }
        .help("Scheme")
        .accessibilityLabel("Scheme: \(model.selectedScheme ?? "None")")
        .disabled(model.schemes.isEmpty)
    }
}
