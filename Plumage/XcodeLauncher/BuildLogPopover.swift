import AppKit
import SwiftUI

struct BuildLogPopover: View {
    @Bindable var model: XcodeRunModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Build Output")
                    .font(.headline)
                Spacer()
                Button {
                    copyFullLog()
                } label: {
                    Label("Copy full log", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.tailLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if model.tailLog.isEmpty {
                        Text("No output yet.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minWidth: 520, minHeight: 320)
        }
        .padding(16)
    }

    private func copyFullLog() {
        let text = model.fullLogText
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
