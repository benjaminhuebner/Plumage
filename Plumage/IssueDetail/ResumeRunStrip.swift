import SwiftUI

struct ResumeRunStrip: View {
    let lastPhase: String?
    let onResume: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.orange)
                .frame(width: 8, height: 8)
            Text(lastPhase.map { "run stopped (\($0))" } ?? "run stopped before finishing")
                .font(.callout.weight(.medium))
            Spacer()
            Button {
                onResume()
            } label: {
                Label("Resume Run", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("Relaunch the implement run — it continues at the next unchecked task")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
        // .contain, not .combine: combining would swallow the button and
        // remove it from the accessibility tree.
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack(spacing: 12) {
        ResumeRunStrip(lastPhase: "failed at task 5", onResume: {})
        ResumeRunStrip(lastPhase: nil, onResume: {})
    }
    .frame(width: 640)
    .padding()
}
