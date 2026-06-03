import SwiftUI

// Middle column: the selected item's files (selectable, drive the right column) plus a
// read-only membership section. A ● marks a file whose override diverges from the bundled
// original. Base offers a "+" to author new files/folders.
//
// Hand-rolled scroll + rows (not `List`/`OutlineGroup`) so the live move-drag can render
// the grabbed row 1:1 under the cursor (the Kanban card pattern). A `List` is AppKit
// `NSTableView` under the hood: it swallows a custom `DragGesture`'s floating overlay and
// draws its own drop outlines that can't be turned off — exactly what we don't want here.
struct TemplateContentColumn: View {
    @Bindable var model: TemplateManagerModel
    @State private var addKind: UserTemplateKind?
    // Live drag: the grabbed row floats under the cursor; the registry tracks row frames
    // so the drop resolves the row under the cursor.
    @State private var drag = TemplateTreeDragController()
    @State private var frames = TemplateTreeFrameRegistry()

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            floatingDragRow
        }
        .coordinateSpace(.named(TemplateTreeCoordinateSpace.name))
        .overlay(alignment: .bottom) { dropBanner }
        .animation(.default, value: model.dropBanner)
        .navigationTitle(model.selectionTitle)
        .toolbar { addToolbar }
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

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if !model.contentFiles.isEmpty {
                    sectionHeader("Files")
                    ForEach(model.contentTree) { node in
                        TemplateTreeRow(
                            node: node, depth: 0, model: model, drag: drag, frames: frames,
                            addKind: $addKind)
                    }
                }

                if let componentID = model.editingComponentID {
                    sectionHeader("Included in templates")
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
                        .padding(.horizontal, 8)
                    }
                } else if let membership = model.membership {
                    sectionHeader(membership.title)
                    if membership.names.isEmpty {
                        Text("None").foregroundStyle(.secondary).padding(.horizontal, 8)
                    } else {
                        ForEach(membership.names, id: \.self) { name in
                            Label(name, systemImage: "puzzlepiece")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                        }
                    }
                }

                if model.contentFiles.isEmpty && model.membership == nil
                    && model.editingComponentID == nil
                {
                    Text("No files").foregroundStyle(.secondary).padding(8)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Finder files dropped on the empty scroll area import into the current selection.
        .dropDestination(for: URL.self) { urls, _ in
            model.importDropped(urls: urls)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The grabbed row rendered 1:1 under the cursor (Kanban `FloatingDragCard` pattern),
    // offset from its lift frame by the live drag translation — a translucent chip with a
    // shadow, like a Finder drag image.
    @ViewBuilder
    private var floatingDragRow: some View {
        if drag.isActive, let node = drag.sourceNode {
            TemplateTreeRowLabel(node: node, model: model, depth: 0, selected: false)
                .padding(.horizontal, 8)
                .frame(width: max(drag.sourceFrame.width, 1), alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .offset(
                    x: drag.sourceFrame.minX + drag.translation.width,
                    y: drag.sourceFrame.minY + drag.translation.height
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var dropBanner: some View {
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

    @ToolbarContentBuilder
    private var addToolbar: some ToolbarContent {
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
}

// One row in the hand-rolled content tree: a folder renders a chevron + children below
// (hand-rolled disclosure), a file renders an icon + name. Selection is a tap that sets
// `model.selectedFile` (the window's `onChange` drives the editor); the live move-drag is
// a pure `DragGesture` feeding the shared controller.
private struct TemplateTreeRow: View {
    let node: FileNode
    let depth: Int
    @Bindable var model: TemplateManagerModel
    let drag: TemplateTreeDragController
    let frames: TemplateTreeFrameRegistry
    @Binding var addKind: UserTemplateKind?
    @State private var expanded = true

    private var isSelected: Bool { model.selectedFile?.relativePath == node.relativePath }

    var body: some View {
        row
        if node.isDirectory, expanded, let children = node.children {
            ForEach(children) { child in
                TemplateTreeRow(
                    node: child, depth: depth + 1, model: model, drag: drag, frames: frames,
                    addKind: $addKind)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(width: 12)
                    .contentShape(Rectangle())
                    .onTapGesture { expanded.toggle() }
            } else {
                Color.clear.frame(width: 12)
            }
            TemplateTreeRowLabel(node: node, model: model, depth: depth, selected: isSelected)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .opacity(drag.sourceNode?.relativePath == node.relativePath ? 0.35 : 1)
        .reportTreeRowFrame(node.relativePath, registry: frames)
        .onTapGesture { model.selectedFile = node }
        .gesture(dragGesture)
        .contextMenu { rowMenu }
        .dropDestination(for: URL.self) { urls, _ in
            model.importDropped(urls: urls, into: node)
            return true
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(TemplateTreeCoordinateSpace.name))
            .onChanged { value in
                if !drag.isActive {
                    drag.startLift(node: node, frame: frames.rows[node.relativePath] ?? .zero)
                }
                drag.updateCursor(location: value.location, translation: value.translation)
            }
            .onEnded { value in
                defer { drag.clear() }
                guard let source = drag.sourceNode, let target = nodeAt(value.location),
                    target.relativePath != source.relativePath
                else { return }
                model.moveNodes([source], into: target)
            }
    }

    private func nodeAt(_ point: CGPoint) -> FileNode? {
        guard let path = frames.rows.first(where: { $0.value.contains(point) })?.key else { return nil }
        return TemplateManagerModel.findNode(in: model.contentTree, relativePath: path)
    }

    @ViewBuilder
    private var rowMenu: some View {
        if !model.addableKinds.isEmpty {
            ForEach(model.addableKinds) { kind in
                Button("Add \(kind.addNoun)…") {
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
            if model.isUserAuthored(node) {
                Divider()
                Button("Delete", role: .destructive) { model.requestDelete(node) }
            }
        }
    }
}

// The icon + name + status markers of a tree row, shared by the row and the floating drag
// chip so they look identical. `selected` flips the foreground for contrast on the accent
// selection fill.
private struct TemplateTreeRowLabel: View {
    let node: FileNode
    @Bindable var model: TemplateManagerModel
    let depth: Int
    let selected: Bool

    var body: some View {
        let needsWiring = node.isDirectory ? model.aggregateNeedsWiring(node) : model.needsWiring(node)
        let overridden = node.isDirectory ? model.aggregateOverridden(node) : model.isOverridden(node)
        HStack(spacing: 6) {
            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if needsWiring {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? Color.white : Color.orange)
                    .opacity(node.isDirectory ? 0.7 : 1)
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
                    .foregroundStyle(
                        selected ? Color.white : (node.isDirectory ? Color.secondary : Color.accentColor)
                    )
                    .accessibilityLabel(node.isDirectory ? "Contains an override" : "Overridden")
            }
        }
        .padding(.leading, CGFloat(depth * 14))
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}
