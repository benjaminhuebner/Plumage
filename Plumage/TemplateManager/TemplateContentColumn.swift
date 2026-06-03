import SwiftUI

// Middle column: the selected item's files (selectable, drive the right column)
// plus a read-only membership section. A ● marks a file whose override diverges
// from the bundled original. Base offers a "+" to author new files/folders.
struct TemplateContentColumn: View {
    @Bindable var model: TemplateManagerModel
    @State private var addKind: UserTemplateKind?

    var body: some View {
        List(selection: $model.selectedFile) {
            if !model.contentFiles.isEmpty {
                Section("Files") {
                    OutlineGroup(model.contentTree, id: \.self, children: \.children) { node in
                        fileRow(node)
                            .tag(node)
                            .contextMenu { rowMenu(node) }
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
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(membership.names, id: \.self) { name in
                            Label(name, systemImage: "puzzlepiece")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if model.contentFiles.isEmpty && model.membership == nil && model.editingComponentID == nil {
                Text("No files")
                    .foregroundStyle(.secondary)
            }
        }
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
                    .foregroundStyle(node.isDirectory ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
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
            if model.isUserAuthored(node) {
                Divider()
                Button("Delete", role: .destructive) { model.requestDelete(node) }
            }
        }
    }
}
