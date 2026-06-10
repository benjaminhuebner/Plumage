import AppKit
import SwiftUI

struct BuildLogPopover: View {
    @Bindable var model: XcodeRunModel
    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Build Output")
                    .font(.headline)
                Spacer()
                Button {
                    copyFullLog()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                Button {
                    isOpen = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Close")
                .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.tailLog) { line in
                        Text(line.text)
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
