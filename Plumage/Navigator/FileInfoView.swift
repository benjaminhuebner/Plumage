import AppKit
import SwiftUI

struct FileInfoView: View {
    let fileURL: URL

    @State private var metadata: Metadata?
    @State private var loadError: String?

    private struct Metadata: Sendable {
        let size: Int64
        let modified: Date?
        let created: Date?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileURL.lastPathComponent)
                        .font(.title3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(fileURL.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            metadataGrid

            actionButtons

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: fileURL) { await loadAttributes() }
    }

    @ViewBuilder
    private var metadataGrid: some View {
        if let metadata {
            VStack(alignment: .leading, spacing: 4) {
                metadataRow(
                    label: "Size", value: ByteCountFormatter.string(fromByteCount: metadata.size, countStyle: .file))
                metadataRow(label: "Modified", value: formattedDate(metadata.modified))
                metadataRow(label: "Created", value: formattedDate(metadata.created))
            }
        } else if let loadError {
            Text(loadError)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            if isXcodeOpenable {
                Button("Open in Xcode") { openInXcode() }
                    .buttonStyle(.borderedProminent)
            }
            Button("Open in Default App") { openDefault() }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        }
    }

    private var isXcodeOpenable: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ext == "swift" || ext == "xcodeproj" || ext == "xcworkspace"
    }

    private func openInXcode() {
        let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")
        NSWorkspace.shared.open(
            [fileURL], withApplicationAt: xcode,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil)
    }

    private func openDefault() {
        NSWorkspace.shared.open(fileURL)
    }

    private func loadAttributes() async {
        let url = fileURL
        let result = await Task.detached(priority: .userInitiated) {
            () -> Result<Metadata, Error> in
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let modified = attrs[.modificationDate] as? Date
                let created = attrs[.creationDate] as? Date
                return .success(Metadata(size: size, modified: modified, created: created))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let meta):
            self.metadata = meta
            self.loadError = nil
        case .failure(let error):
            self.metadata = nil
            self.loadError = "Couldn't read file: \(error.localizedDescription)"
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
