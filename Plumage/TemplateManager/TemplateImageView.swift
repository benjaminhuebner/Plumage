import SwiftUI

// One renderer for both `TemplateImage` cases: an SF Symbol, or an imported image
// file resolved through the override store. Used by the sidebar and the
// New/Migrate grids so a custom template's image shows everywhere.
struct TemplateImageView: View {
    let image: TemplateImage
    let resolve: (String) -> URL?

    var body: some View {
        switch image {
        case .symbol(let name):
            Image(systemName: name)
        case .file(let relativePath):
            if let url = resolve(relativePath), let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
            }
        }
    }
}
