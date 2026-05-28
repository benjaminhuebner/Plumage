import AppKit
import SwiftUI

// Inline image preview shown in the detail pane when an image file is
// single-clicked in the sidebar. Wraps `NSImageView` so we get free
// .aspectRatio(.fit) + zoom-to-fit behavior with no manual scaling logic.
// Bitmap data is loaded on a background task; .task(id:) re-triggers when
// the URL changes (FSEvents-triggered reload swap or selection change).
struct ImagePreviewView: View {
    let fileURL: URL

    @State private var image: NSImage?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 8) {
            if let image {
                ImageHost(image: image)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn't load image",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 10) {
                Text(fileURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .task(id: fileURL) { await loadImage() }
    }

    private func loadImage() async {
        let url = fileURL
        let loaded = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
        if let loaded {
            self.image = loaded
            self.loadError = nil
        } else {
            self.image = nil
            self.loadError = "Image data could not be decoded."
        }
    }
}

private struct ImageHost: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.image = image
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = image
    }
}
