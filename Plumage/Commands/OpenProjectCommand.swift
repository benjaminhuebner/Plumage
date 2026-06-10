import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum OpenProjectCommand {
    static let plumageProjectUTI = "com.benjaminhuebner.plumage.project"

    static func openWithPicker(
        recentProjects: RecentProjects,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction,
        onMigrate: ((URL) -> Void)? = nil
    ) {
        guard let url = pickProject() else { return }
        openFromBundleURL(
            url,
            recentProjects: recentProjects,
            openWindow: openWindow,
            dismissWindow: dismissWindow,
            onMigrate: onMigrate
        )
    }

    static func openConfirmed(
        url: URL,
        recentProjects: RecentProjects,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction,
        onMigrate: ((URL) -> Void)? = nil
    ) {
        let bundle: URL
        do {
            bundle = try BundleResolver.findBundle(in: url)
        } catch let error as BundleResolver.ResolveError {
            presentAlertForResolverError(error, folder: url, onMigrate: onMigrate)
            return
        } catch {
            assertionFailure("BundleResolver.findBundle threw non-ResolveError: \(error)")
            return
        }
        completeOpen(
            root: url,
            bundle: bundle,
            recentProjects: recentProjects,
            openWindow: openWindow,
            dismissWindow: dismissWindow
        )
    }

    static func openFromBundleURL(
        _ url: URL,
        recentProjects: RecentProjects,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction,
        onMigrate: ((URL) -> Void)? = nil
    ) {
        let resolved: (root: URL, bundle: URL)
        do {
            resolved = try BundleResolver.resolve(from: url)
        } catch let error as BundleResolver.ResolveError {
            presentAlertForResolverError(error, folder: url, onMigrate: onMigrate)
            return
        } catch {
            assertionFailure("BundleResolver.resolve threw non-ResolveError: \(error)")
            return
        }
        completeOpen(
            root: resolved.root,
            bundle: resolved.bundle,
            recentProjects: recentProjects,
            openWindow: openWindow,
            dismissWindow: dismissWindow
        )
    }

    private static func presentAlertForResolverError(
        _ error: BundleResolver.ResolveError,
        folder: URL,
        onMigrate: ((URL) -> Void)? = nil
    ) {
        switch error {
        case .noBundle:
            presentAlert(for: .noBundle(folder: folder), migrateFolder: folder, onMigrate: onMigrate)
        case .multipleBundles(let urls):
            presentAlert(for: .multipleBundles(found: urls))
        }
    }

    private static func completeOpen(
        root: URL,
        bundle: URL,
        recentProjects: RecentProjects,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction
    ) {
        do {
            let config = try ConfigLoader.load(atBundle: bundle)
            recentProjects.add(url: root, name: config.name)
            // Feeds the system recents (Dock menu, NSDocumentController) in
            // addition to Plumage's own store — the bundle is the registered
            // document type, so LaunchServices routes a Dock-recent click
            // back through application(_:open:).
            NSDocumentController.shared.noteNewRecentDocumentURL(bundle)
            openWindow(value: ProjectHandle(url: root))
            dismissWindow(id: "welcome")
        } catch let error as ConfigLoader.LoadError {
            presentAlert(for: error)
        } catch {
            presentAlert(for: .invalidJSON(message: error.localizedDescription))
        }
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
        var allowed: [UTType] = [.folder]
        if let bundleType = UTType(plumageProjectUTI) {
            allowed.append(bundleType)
        }
        panel.allowedContentTypes = allowed
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func presentAlert(
        for error: ConfigLoader.LoadError,
        migrateFolder: URL? = nil,
        onMigrate: ((URL) -> Void)? = nil
    ) {
        let alert = NSAlert()
        switch error {
        case .noBundle(let folder):
            alert.messageText = "Not a Plumage project"
            alert.informativeText = "No .plumage bundle found at \(folder.path)."
            if let migrateFolder, let onMigrate {
                alert.informativeText += "\n\nMigrate this folder to make it a Plumage project?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Migrate This Folder…")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    onMigrate(migrateFolder)
                }
                return
            }
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

struct OpenRecentMenu: View {
    // Injected, not @Environment: CommandGroup views don't inherit the scene environment.
    let recentProjects: RecentProjects

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Menu("Open Recent") {
            ForEach(recentProjects.items) { item in
                Button(item.name) {
                    OpenProjectCommand.openFromBundleURL(
                        item.url,
                        recentProjects: recentProjects,
                        openWindow: openWindow,
                        dismissWindow: dismissWindow
                    )
                }
            }
            if !recentProjects.items.isEmpty {
                Divider()
                Button("Clear Menu") {
                    recentProjects.clear()
                    NSDocumentController.shared.clearRecentDocuments(nil)
                }
            }
        }
        .disabled(recentProjects.items.isEmpty)
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
