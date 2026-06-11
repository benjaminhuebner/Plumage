import AppKit
import SwiftUI

// The one visual language both trees share: real workspace icon + name.
struct FinderFileTreeRowLabel: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: 6) {
            FinderFileTreeRowIcon(node: node)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct FinderFileTreeRowIcon: View {
    let node: FileNode

    var body: some View {
        Image(
            nsImage: WorkspaceIconCache.icon(
                forPath: node.url.path, isDirectory: node.isDirectory)
        )
        .resizable()
        .frame(width: 16, height: 16)
    }
}
