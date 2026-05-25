import SwiftUI

struct TerminalTabBar: View {
    let model: TerminalTabsModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.tabs) { tab in
                TerminalTabPill(
                    tab: tab,
                    isActive: tab.id == model.selectedTabID,
                    canClose: model.canClose(tab.id),
                    onSelect: { model.selectedTabID = tab.id },
                    onClose: { model.closeTab(id: tab.id) }
                )
            }
            Spacer(minLength: 4)
            Button {
                model.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New Terminal Tab")
            .accessibilityLabel("New Terminal Tab")
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct TerminalTabPill: View {
    let tab: TerminalTab
    let isActive: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if canClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            // Keep the slot allocated when not visible so
                            // hover-in doesn't reflow the row width.
                            .opacity(isActive || isHovering ? 1.0 : 0.0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close \(tab.title)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.35) : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

#Preview {
    @Previewable @State var model: TerminalTabsModel = {
        let binary = URL(filePath: "/usr/bin/true")
        let session = TerminalClaudeSession(cwd: URL(filePath: "/tmp"), binaryURL: binary)
        return TerminalTabsModel(
            cwd: URL(filePath: "/tmp"),
            binaryURL: binary,
            initialSession: session
        )
    }()
    return TerminalTabBar(model: model)
        .frame(width: 480)
        .padding()
}
