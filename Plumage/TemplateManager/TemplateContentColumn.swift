import SwiftUI

// Middle column: the selected item's files (selectable, drive the right column) plus a
// read-only membership section. A ● marks a file whose override diverges from the bundled
// original. Base offers a "+" to author new files/folders.
//
// Drag-and-drop is the idiomatic SwiftUI pair on the native `List`/`OutlineGroup`:
// `.draggable` (the system drag image follows the cursor, like Finder) plus
// `.dropDestination`. Same pattern as the Navigator's file tree.
struct TemplateContentColumn: View {
    @Bindable var model: TemplateManagerModel
    @State private var addKind: UserTemplateKind?

    var body: some View {
        List(selection: $model.selectedFile) {
            if !model.contentFiles.isEmpty {
                Section("Files") {
                    ForEach(visibleRows(), id: \.node.id) { row in
                        contentRow(row.node, depth: row.depth)
                    }
                }
            }

            if let componentID = model.editingComponentID {
                Section("Included in templates") {
                    ForEach(model.catalog.templates.sorted { $0.name < $1.name }) { template in
                        Toggle(
                            isOn: Binding(
                                get: { model.isMember(componentID: componentID, templateID: template.id) },
                                set: {
                                    model.setMembership(
                                        componentID: componentID, templateID: template.id, isMember: $0)
                                })
                        ) {
                            Text(template.name)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            } else if let membership = model.membership {
                Section(membership.title) {
                    if membership.names.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        ForEach(membership.names, id: \.self) { name in
                            Label(name, systemImage: "puzzlepiece").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if model.contentFiles.isEmpty && model.membership == nil && model.editingComponentID == nil {
                Text("No files").foregroundStyle(.secondary)
            }
        }
        // Finder files dropped on the empty list area import into the current selection.
        .dropDestination(for: URL.self) { urls, _ in
            model.importDropped(urls: urls)
        }
        .overlay(alignment: .bottom) {
            if let banner = model.dropBanner {
                Text(banner)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: model.dropBanner)
        .navigationTitle(model.selectionTitle)
        .toolbar {
            if !model.addableKinds.isEmpty {
                ToolbarItemGroup {
                    ForEach(model.addableKinds) { kind in
                        Button {
                            addKind = kind
                        } label: {
                            Label("Add \(kind.addNoun)", systemImage: kind.sfSymbolName)
                        }
                        .help("Add \(kind.addNoun) in the selected folder")
                    }
                }
            }
        }
        .sheet(item: $addKind) { kind in
            TemplateAddSheet(kind: kind) { name in
                model.addUserFile(kind: kind, rawName: name) != nil
            }
        }
        .sheet(item: $model.pendingHookWiring) { hook in
            HookWiringSheet(hookName: hook.name, initial: model.wiring(forHook: hook)) { event, matcher in
                model.saveWiring(forHook: hook, event: event, matcher: matcher)
            }
        }
        .confirmationDialog(
            model.pendingDeleteConfirmation.map { "Delete “\($0.name)” and its contents?" } ?? "",
            isPresented: Binding(
                get: { model.pendingDeleteConfirmation != nil },
                set: { if !$0 { model.pendingDeleteConfirmation = nil } }),
            titleVisibility: .visible,
            presenting: model.pendingDeleteConfirmation
        ) { _ in
            Button("Move to Trash", role: .destructive) { model.confirmPendingDelete() }
            Button("Cancel", role: .cancel) { model.pendingDeleteConfirmation = nil }
        } message: { _ in
            Text("This folder and everything in it will be moved to the Trash.")
        }
    }

    // One row per visible node. A `DisclosureGroup` label is not a reliable drop target,
    // so the tree is a flat `List` of rows with manual indentation and a disclosure
    // chevron — `.draggable`/`.dropDestination` then work on every row exactly as the old
    // `OutlineGroup` did, while expansion stays model-driven so created/moved items reveal.
    private struct VisibleRow {
        let node: FileNode
        let depth: Int
    }

    private func visibleRows() -> [VisibleRow] {
        var rows: [VisibleRow] = []
        func walk(_ nodes: [FileNode], _ depth: Int) {
            for node in nodes {
                rows.append(VisibleRow(node: node, depth: depth))
                if let children = node.children, model.isNodeExpanded(node.id) {
                    walk(children, depth + 1)
                }
            }
        }
        walk(model.contentTree, 0)
        return rows
    }

    private func contentRow(_ node: FileNode, depth: Int) -> some View {
        HStack(spacing: 4) {
            if node.children != nil {
                Button {
                    model.setNode(node.id, expanded: !model.isNodeExpanded(node.id))
                } label: {
                    Image(systemName: model.isNodeExpanded(node.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12)
            }
            fileRow(node)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .tag(node)
        .contentShape(Rectangle())
        .contextMenu { rowMenu(node) }
        .draggable(FileTreeDragPayload(url: node.url))
        .dropDestination(for: DroppableTreeItem.self) { items, _ in
            return handleDrop(items, onto: node)
        }
    }

    // Internal nodes move into the row's folder, Finder URLs import there. `moveNodes`
    // maps a file row to its parent folder and rejects no-ops.
    private func handleDrop(_ items: [DroppableTreeItem], onto node: FileNode) -> Bool {
        var finderURLs: [URL] = []
        var moveSources: [FileNode] = []
        for item in items {
            switch item {
            case .finderURL(let url): finderURLs.append(url)
            case .internalNode(let payload):
                if let source = model.contentNode(forURL: payload.url) { moveSources.append(source) }
            }
        }
        if !moveSources.isEmpty { model.moveNodes(moveSources, into: node) }
        if !finderURLs.isEmpty { model.importDropped(urls: finderURLs, into: node) }
        return !moveSources.isEmpty || !finderURLs.isEmpty
    }

    private func fileRow(_ node: FileNode) -> some View {
        let needsWiring = node.isDirectory ? model.aggregateNeedsWiring(node) : model.needsWiring(node)
        let overridden = node.isDirectory ? model.aggregateOverridden(node) : model.isOverridden(node)
        return HStack(spacing: 6) {
            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
            Spacer(minLength: 0)
            if needsWiring {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .opacity(node.isDirectory ? 0.6 : 1)
                    .help(
                        node.isDirectory
                            ? "A hook inside is not wired into settings.json yet"
                            : "This hook is not wired into settings.json yet"
                    )
                    .accessibilityLabel(node.isDirectory ? "Contains an unwired hook" : "Needs wiring")
            }
            if overridden {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(node.isDirectory ? Color.secondary : Color.accentColor)
                    .accessibilityLabel(node.isDirectory ? "Contains an override" : "Overridden")
            }
        }
    }

    @ViewBuilder
    private func addMenu(into target: FileNode? = nil) -> some View {
        ForEach(model.addableKinds) { kind in
            Button("Add \(kind.addNoun)…") {
                // A row's menu targets that row; the toolbar menu uses the selection.
                if let target { model.selectedFile = target }
                addKind = kind
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ node: FileNode) -> some View {
        if !model.addableKinds.isEmpty {
            addMenu(into: node)
            Divider()
        }
        if !node.isDirectory {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            if model.isHook(node) {
                Button(model.needsWiring(node) ? "Set Wiring…" : "Edit Wiring…") {
                    model.pendingHookWiring = node
                }
            }
        }
        // Delete is offered for any user-authored item, file or folder.
        if model.isUserAuthored(node) {
            Divider()
            Button("Delete", role: .destructive) { model.requestDelete(node) }
        }
    }
}
