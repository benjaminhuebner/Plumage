import SwiftUI

struct RunStatusPill: View {
    @Bindable var model: XcodeRunModel
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 6) {
                switch model.runState {
                case .idle:
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                    Text("Idle")
                case .building:
                    ProgressView()
                        .controlSize(.small)
                    Text("Building…")
                case .running:
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.green)
                    Text("Running")
                case .failed(let message):
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .lineLimit(1)
                }
            }
        }
        .help("Show build output")
        .buttonStyle(.plain)
    }
}
