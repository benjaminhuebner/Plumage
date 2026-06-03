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
                    ForEach(model.contentFiles) { node in
                        fileRow(node)
                            .tag(node)
                            .contextMenu { rowMenu(node) }
                    }
                }
            }

            if let membership = model.membership {
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

            if model.contentFiles.isEmpty && model.membership == nil {
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
                ToolbarItem {
                    Menu {
                        addMenu()
                    } label: {
                        Label("Add", systemImage: "plus")
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
    }

    private func fileRow(_ node: FileNode) -> some View {
        HStack(spacing: 6) {
            Label(node.name, systemImage: "doc.text")
            Spacer(minLength: 0)
            if model.needsWiring(node) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("This hook is not wired into settings.json yet")
                    .accessibilityLabel("Needs wiring")
            }
            if model.isOverridden(node) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Overridden")
            }
        }
    }

    @ViewBuilder
    private func addMenu() -> some View {
        ForEach(model.addableKinds) { kind in
            Button("Add \(kind.addNoun)…") { addKind = kind }
        }
    }

    @ViewBuilder
    private func rowMenu(_ node: FileNode) -> some View {
        if !model.addableKinds.isEmpty {
            addMenu()
            Divider()
        }
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
            Button("Delete", role: .destructive) { model.delete(node) }
        }
    }
}
