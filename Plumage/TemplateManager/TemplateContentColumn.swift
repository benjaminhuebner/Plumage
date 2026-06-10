import AppKit
import SwiftUI

// Middle column: the selected item's files (selectable, drive the right column) plus a
// read-only membership section. A ● marks a file whose override diverges from the bundled
// original. Base offers a "+" to author new files/folders.
struct TemplateContentColumn: View {
    @Bindable var model: TemplateManagerModel
    @State private var addKind: UserTemplateKind?

    var body: some View {
        VStack(spacing: 0) {
            contentArea
            membershipArea
        }
        // Finder files dropped outside the tree (membership area, empty state)
        // import into the current selection; drops on tree rows are handled by
        // the outline view itself.
        .dropDestination(for: URL.self) { urls, _ in
            model.importDropped(urls: urls)
        }
        .overlay(alignment: .bottom) {
            if let banner = model.dropBanner {
                Text(banner)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.background.secondary, in: Capsule())
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
        .confirmationDialog(
            "Delete \(model.pendingBatchDelete?.count ?? 0) items?",
            isPresented: Binding(
                get: { model.pendingBatchDelete != nil },
                set: { if !$0 { model.pendingBatchDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { model.confirmPendingBatchDelete() }
            Button("Cancel", role: .cancel) { model.pendingBatchDelete = nil }
        } message: {
            Text("The selected items will be moved to the Trash.")
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if !model.contentTree.isEmpty {
            Text("Files")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 4)
            fileTree
        } else if model.membership == nil && model.editingComponentID == nil {
            Spacer(minLength: 0)
            Text("No files").foregroundStyle(.secondary)
            Spacer(minLength: 0)
        } else {
            Spacer(minLength: 0)
        }
    }

    private var fileTree: some View {
        FinderFileTree(
            nodes: model.contentTree,
            style: .inset,
            expandedPaths: $model.contentExpandedPaths,
            selectedPath: model.selectedFile?.relativePath,
            revealRequest: model.contentReveal,
            contextMenu: { nodes in
                if nodes.count > 1 {
                    guard model.canBatchDelete(nodes) else { return nil }
                    return NSHostingMenu(
                        rootView: TemplateContentBatchMenu(model: model, nodes: nodes))
                }
                guard let node = nodes.first else { return nil }
                return NSHostingMenu(
                    rootView: TemplateContentRowMenu(model: model, node: node, addKind: $addKind))
            },
            onRenameRequest: { node in model.beginRenameContent(node) },
            onTrashRequest: { nodes in model.requestDelete(batch: nodes) },
            canDrag: { node in !model.isReadOnlyContentNode(node) },
            validateDrop: { payload, target in
                switch payload {
                case .internalMove:
                    guard let target else { return false }
                    return TemplateContentDropResolver.targetStoreDir(
                        for: target, scope: model.activeScope) != nil
                case .finderCopy:
                    return true
                }
            },
            onDrop: { payload, target in
                switch payload {
                case .internalMove(let urls):
                    guard let target else { return false }
                    let sources = urls.compactMap { model.contentNode(forURL: $0) }
                    guard !sources.isEmpty else { return false }
                    model.moveNodes(sources, into: target)
                    return true
                case .finderCopy(let urls):
                    return model.importDropped(urls: urls, into: target)
                }
            },
            onSelect: { node in model.selectedFile = node },
            rowContent: { node in TemplateContentRow(model: model, node: node) }
        )
    }

    @ViewBuilder
    private var membershipArea: some View {
        if let componentID = model.editingComponentID {
            Divider()
            List {
                Section("Included in templates") {
                    ForEach(model.catalog.templatesSortedByName) { template in
                        Toggle(
                            isOn: model.membershipBinding(
                                componentID: componentID, templateID: template.id)
                        ) {
                            Text(template.name)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: membershipMaxHeight)
        } else if let membership = model.membership {
            Divider()
            List {
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
            .frame(maxHeight: membershipMaxHeight)
        }
    }

    // With no file tree above, the membership list owns the column.
    private var membershipMaxHeight: CGFloat? {
        model.contentTree.isEmpty ? nil : 240
    }
}

private struct TemplateContentRow: View {
    let model: TemplateManagerModel
    let node: FileNode

    var body: some View {
        let needsWiring =
            node.isDirectory ? model.aggregateNeedsWiring(node) : model.needsWiring(node)
        let overridden =
            node.isDirectory ? model.aggregateOverridden(node) : model.isOverridden(node)
        HStack(spacing: 6) {
            if model.contentRename?.id == node.id {
                FinderFileTreeRowIcon(node: node)
                FinderFileTreeRenameField(
                    text: model.contentRenameNameBinding,
                    placeholder: node.name,
                    onCommit: { model.commitContentRename() },
                    onCancel: { model.cancelContentRename() })
            } else {
                FinderFileTreeRowLabel(node: node)
            }
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
        .padding(.vertical, 2)
    }
}

private struct TemplateContentBatchMenu: View {
    let model: TemplateManagerModel
    let nodes: [FileNode]

    var body: some View {
        Button("Move \(nodes.count) Items to Trash", role: .destructive) {
            model.requestDelete(batch: nodes)
        }
    }
}

private struct TemplateContentRowMenu: View {
    let model: TemplateManagerModel
    let node: FileNode
    @Binding var addKind: UserTemplateKind?

    var body: some View {
        if !model.addableKinds.isEmpty {
            ForEach(model.addableKinds) { kind in
                Button("Add \(kind.addNoun)…") {
                    // A row's menu targets that row; the toolbar menu uses the selection.
                    model.selectedFile = node
                    addKind = kind
                }
            }
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
        // Rename + Delete are offered for any user-authored item, file or folder.
        if model.isUserAuthored(node) {
            Divider()
            Button("Rename") { model.beginRenameContent(node) }
            Button("Delete", role: .destructive) { model.requestDelete(node) }
        }
    }
}
