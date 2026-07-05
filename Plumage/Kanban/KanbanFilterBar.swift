import SwiftUI

struct KanbanFilterBar: View {
    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(\.issueTypeCatalog) private var issueTypeCatalog

    var body: some View {
        @Bindable var kanban = kanban
        // Scrollable failsafe: the bar must never impose a minimum width on
        // the detail column — an over-wide detail child gets clipped and takes
        // the board's scroll viewport out of reach with it.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                searchField(text: $kanban.filter.text)
                labelMenu
                typeMenu
                activeTokens
                if kanban.filter.isActive {
                    Button("Clear All") {
                        kanban.clearFilter()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Clear all filters")
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text("Reorder within a column is paused while filtering")
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .font(.callout)
        }
    }

    private func searchField(text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Filter by title, id, or label", text: text)
                .textFieldStyle(.plain)
                .accessibilityLabel("Filter issues")
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.quaternarySystemFill), in: Capsule())
        .frame(width: 240, alignment: .leading)
    }

    private var labelMenu: some View {
        Menu {
            ForEach(kanban.availableFilterLabels, id: \.self) { label in
                Button {
                    toggleLabel(label)
                } label: {
                    HStack {
                        Text(label)
                        if kanban.filter.selectedLabels.contains(label) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Labels", systemImage: "tag")
        }
        .fixedSize()
        .disabled(kanban.availableFilterLabels.isEmpty)
        .accessibilityLabel("Filter by label")
    }

    private var typeMenu: some View {
        Menu {
            Button {
                kanban.filter.type = nil
            } label: {
                HStack {
                    Text("Any")
                    if kanban.filter.type == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Divider()
            ForEach(issueTypeCatalog.types, id: \.self) { type in
                Button {
                    kanban.filter.type = type
                } label: {
                    HStack {
                        Text(type.rawValue.capitalized)
                        if kanban.filter.type == type {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(kanban.filter.type?.rawValue.capitalized ?? "Type", systemImage: "square.grid.2x2")
        }
        .fixedSize()
        .accessibilityLabel("Filter by type")
    }

    @ViewBuilder
    private var activeTokens: some View {
        ForEach(kanban.filter.selectedLabels.sorted(), id: \.self) { label in
            LabelChip(text: label) {
                toggleLabel(label)
            }
        }
        if let type = kanban.filter.type {
            HStack(spacing: 4) {
                Text(type.rawValue.capitalized)
                    .font(.body.monospaced())
                Button {
                    kanban.filter.type = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove type filter")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(NSColor.tertiarySystemFill), in: Capsule())
        }
    }

    private func toggleLabel(_ label: String) {
        if kanban.filter.selectedLabels.contains(label) {
            kanban.filter.selectedLabels.remove(label)
        } else {
            kanban.filter.selectedLabels.insert(label)
        }
    }
}

#Preview {
    KanbanFilterBar()
        .padding()
        .frame(width: 900)
        .environment(ProjectKanbanModel())
}
