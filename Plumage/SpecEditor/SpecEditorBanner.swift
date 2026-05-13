import SwiftUI

struct SpecEditorBanner: View {
    let frontmatterError: FrontmatterError?
    let conflict: SpecEditorModel.ConflictState?
    let onJumpToError: () -> Void
    let onReload: () -> Void
    let onKeep: () -> Void
    let onSaveAndRecreate: () -> Void
    let onDiscard: () -> Void

    @State private var detailsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if let error = frontmatterError {
                frontmatterBanner(for: error)
            }
            if let conflict {
                switch conflict {
                case .externalChange:
                    externalChangeBanner
                case .fileDeleted:
                    fileDeletedBanner
                }
            }
        }
    }

    private func frontmatterBanner(for error: FrontmatterError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error.summary)
                    .font(.headline)
                Spacer()
                Button("Jump to line", action: onJumpToError)
                    .buttonStyle(.borderless)
                Button {
                    detailsExpanded.toggle()
                } label: {
                    Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .help(detailsExpanded ? "Hide details" : "Show details")
            }
            if detailsExpanded {
                Text(error.description)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.28))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.red.opacity(0.5)), alignment: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Frontmatter error: \(error.summary)")
    }

    private var externalChangeBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text("Disk version changed externally")
                .font(.headline)
            Spacer()
            Button("Reload from disk", action: onReload)
                .buttonStyle(.borderless)
            Button("Keep mine", action: onKeep)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.3))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.orange.opacity(0.55)), alignment: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Disk version changed externally")
    }

    private var fileDeletedBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "trash")
                .foregroundStyle(.red)
            Text("File deleted from disk")
                .font(.headline)
            Spacer()
            Button("Save & recreate", action: onSaveAndRecreate)
                .buttonStyle(.borderless)
            Button("Discard", action: onDiscard)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.32))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.red.opacity(0.55)), alignment: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File deleted from disk")
    }
}

#Preview("All banners") {
    VStack(spacing: 0) {
        SpecEditorBanner(
            frontmatterError: .invalidYAML(line: 7, column: 12, message: "unclosed quote"),
            conflict: .externalChange(diskContent: "..."),
            onJumpToError: {},
            onReload: {},
            onKeep: {},
            onSaveAndRecreate: {},
            onDiscard: {}
        )
        Spacer()
    }
    .frame(width: 700, height: 240)
}
