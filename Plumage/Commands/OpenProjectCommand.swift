import AppKit
import SwiftUI

@MainActor
enum OpenProjectCommand {
    static func openWithPicker(
        recentProjects: RecentProjects,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction
    ) {
        guard let url = pickProject() else { return }
        openFromBundleURL(
            url,
            recentProjects: recentProjects,
            openWindow: openWindow,
            dismissWindow: dismissWindow
        )
    }

    static func openConfirmed(
        url: URL,
        recentProjects: RecentProjects,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction
    ) {
        do {
            let config = try ConfigLoader.load(at: url)
            recentProjects.add(url: url, name: config.name)
            openWindow(value: ProjectHandle(url: url))
            dismissWindow(id: "welcome")
        } catch let error as ConfigLoader.LoadError {
            presentAlert(for: error)
        } catch {
            presentAlert(for: .invalidJSON(message: error.localizedDescription))
        }
    }

    static func openFromBundleURL(
        _ url: URL,
        recentProjects: RecentProjects,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction
    ) {
        let root: URL
        do {
            root = try BundleResolver.resolve(from: url).root
        } catch let error as BundleResolver.ResolveError {
            switch error {
            case .noBundle(let folder):
                presentAlert(for: .noBundle(folder: folder))
            case .multipleBundles(let urls):
                presentAlert(for: .multipleBundles(found: urls))
            }
            return
        } catch {
            assertionFailure("BundleResolver.resolve threw non-ResolveError: \(error)")
            return
        }
        openConfirmed(
            url: root,
            recentProjects: recentProjects,
            openWindow: openWindow,
            dismissWindow: dismissWindow
        )
    }

    private static func pickProject() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Open Plumage Project"
        panel.message = "Pick a .plumage bundle or its parent folder."
        panel.prompt = "Open"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func presentAlert(for error: ConfigLoader.LoadError) {
        let alert = NSAlert()
        switch error {
        case .noBundle(let folder):
            alert.messageText = "Not a Plumage project"
            alert.informativeText = "No .plumage bundle found at \(folder.path)."
        case .noConfigFile(let bundle):
            alert.messageText = "Plumage bundle is missing config.json"
            alert.informativeText = "Bundle at \(bundle.path) has no config.json."
        case .multipleBundles(let urls):
            alert.messageText = "Multiple Plumage bundles found"
            let names = urls.map { $0.lastPathComponent }.joined(separator: ", ")
            alert.informativeText = "Found: \(names). Plumage expects exactly one."
        case .schemaTooNew(let version, let supportedUpTo):
            alert.messageText = "This project needs a newer Plumage"
            alert.informativeText =
                "Config schemaVersion is \(version); this build supports up to \(supportedUpTo)."
        case .invalidJSON(let message):
            alert.messageText = "This Plumage config is invalid"
            alert.informativeText = message
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct OpenProjectMenuButton: View {
    // Injected, not @Environment: CommandGroup views don't inherit the scene environment.
    // See notes.md (#00002-open-project).
    let recentProjects: RecentProjects

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button("Open Project…") {
            OpenProjectCommand.openWithPicker(
                recentProjects: recentProjects,
                openWindow: openWindow,
                dismissWindow: dismissWindow
            )
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}
