import AppKit
import SwiftUI

struct NavigatorFileMenu: View {
    let node: FileNode
    let projectURL: URL
    let navigator: NavigatorModel
    let pinModel: PinnedFilesModel

    var body: some View {
        if node.isDirectory {
            Button("New File") {
                Task {
                    await navigator.createAndReveal(
                        parent: node.url, isFolder: false, projectURL: projectURL)
                }
            }
            Button("New Folder") {
                Task {
                    await navigator.createAndReveal(
                        parent: node.url, isFolder: true, projectURL: projectURL)
                }
            }
            Divider()
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        Button("Rename") { navigator.beginRename(url: node.url) }
        if !node.isDirectory {
            Button(pinModel.contains(node.relativePath) ? "Unpin" : "Pin") {
                pinModel.toggle(relativePath: node.relativePath, projectURL: projectURL)
            }
        }
        Button("Move to Trash", role: .destructive) {
            navigator.requestTrash(url: node.url)
        }
    }
}
