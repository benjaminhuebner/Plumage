import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum OpenProjectCommand {
    static let plumageProjectUTI = "com.benjaminhuebner.plumage.project"

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
        let bundle: URL
        do {
            bundle = try BundleResolver.findBundle(in: url)
        } catch let error as BundleResolver.ResolveError {
            presentAlertForResolverError(error)
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
        dismissWindow: DismissWindowAction
    ) {
        let resolved: (root: URL, bundle: URL)
        do {
            resolved = try BundleResolver.resolve(from: url)
        } catch let error as BundleResolver.ResolveError {
            presentAlertForResolverError(error)
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

    private static func presentAlertForResolverError(_ error: BundleResolver.ResolveError) {
        switch error {
        case .noBundle(let folder):
            presentAlert(for: .noBundle(folder: folder))
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

struct OpenProjectMenuCommand: Commands {
    let recentProjects: RecentProjects

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            OpenProjectMenuButton(recentProjects: recentProjects)
        }
    }
}
