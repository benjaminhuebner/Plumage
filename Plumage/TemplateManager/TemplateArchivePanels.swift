import AppKit
import SwiftUI

// One save/open-panel implementation shared by the window toolbar and the
// sidebar context menus, so the two entry points can't drift.
@MainActor
enum TemplateArchivePanels {
    static func presentExport(for selection: TemplateArchiveSelection, model: TemplateManagerModel) {
        let panel = NSSavePanel()
        panel.title = "Export Templates"
        panel.nameFieldLabel = "Export As:"
        panel.nameFieldStringValue = model.exportSuggestedFileName(for: selection)
        panel.allowedContentTypes = [TemplateArchiveFileType.utType]
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.export(selection, to: url) }
        }
    }

    static func presentImport(model: TemplateManagerModel) {
        let panel = NSOpenPanel()
        panel.title = "Import Templates"
        panel.message = "Pick a .\(TemplateArchiveFileType.fileExtension) export file."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [TemplateArchiveFileType.utType]
        panel.prompt = "Import"
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.beginImport(fromArchive: url) }
        }
    }
}
