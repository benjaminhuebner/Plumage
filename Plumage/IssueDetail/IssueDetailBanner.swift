import SwiftUI

struct IssueDetailBanner: View {
    let frontmatterError: FrontmatterError?
    let conflict: IssueDetailModel.ConflictState?
    let onReload: () -> Void
    let onKeep: () -> Void

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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("Frontmatter has errors — fields disabled")
                .font(.headline)
            Spacer()
            Text(error.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.28))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.red.opacity(0.5)), alignment: .bottom)
    }

    private var externalChangeBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text("Disk version changed externally")
                .font(.headline)
            Spacer()
            Button("Use disk", action: onReload)
                .buttonStyle(.borderless)
            Button("Keep mine", action: onKeep)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.3))
        .overlay(
            Rectangle().frame(height: 1).foregroundStyle(.orange.opacity(0.55)), alignment: .bottom
        )
    }

    private var fileDeletedBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "trash")
                .foregroundStyle(.red)
            Text("File deleted from disk")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.32))
    }
}
