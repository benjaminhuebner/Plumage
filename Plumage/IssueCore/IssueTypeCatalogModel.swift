import Foundation
import Observation
import os

@MainActor
@Observable
final class IssueTypeCatalogModel {
    private(set) var catalog: IssueTypeCatalog = .builtIn

    private let store: IssueTypeCatalogStore
    private var loaded = false

    private static let logger = Logger(subsystem: "com.plumage", category: "IssueTypeCatalogModel")

    init(store: IssueTypeCatalogStore = IssueTypeCatalogStore()) {
        self.store = store
    }

    // Off-main disk read; idempotent so every window scene can await it.
    func load() async {
        guard !loaded else { return }
        loaded = true
        let store = self.store
        catalog = await Task.detached(priority: .userInitiated) { store.load() }.value
    }

    func add(name: String, colorHex: String? = nil) throws {
        var copy = catalog
        try copy.add(name: name, colorHex: colorHex)
        commit(copy)
    }

    func remove(_ type: IssueType) throws {
        var copy = catalog
        try copy.remove(type)
        commit(copy)
    }

    func setDraftBlocksImplement(_ blocks: Bool, for type: IssueType) {
        var copy = catalog
        copy.setDraftBlocksImplement(blocks, for: type)
        commit(copy)
    }

    func setColor(_ hex: String?, for type: IssueType) {
        var copy = catalog
        copy.setColor(hex, for: type)
        commit(copy)
    }

    func setDefaultType(_ type: IssueType) {
        var copy = catalog
        copy.setDefaultType(type)
        commit(copy)
    }

    // Persist synchronously: mutations are discrete user actions on a <1 KB
    // file, same trade-off as RecentProjects.persist.
    private func commit(_ newValue: IssueTypeCatalog) {
        catalog = newValue
        do {
            try store.save(newValue)
        } catch {
            Self.logger.warning(
                "issue-type catalog save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
