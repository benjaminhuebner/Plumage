import SwiftUI

struct TerminalTabBar: View {
    let model: TerminalTabsModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tabs) { tab in
                TerminalTabPill(
                    tab: tab,
                    isActive: tab.id == model.selectedTabID,
                    canClose: model.canCloseActiveTab,
                    onSelect: { model.selectedTabID = tab.id },
                    onClose: { model.closeTab(id: tab.id) }
                )
            }
            Spacer(minLength: 4)
            Button {
                model.addTab()
            } label: {
                Image(systemName: "plus")
                    .imageScale(.small)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New Terminal Tab")
            .accessibilityLabel("New Terminal Tab")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        // Keep the slot allocated when not visible so hover-in
                        // doesn't reflow the row width.
                        .opacity(closeButtonOpacity)
                }
                .buttonStyle(.plain)
                .disabled(!canClose)
                .accessibilityLabel("Close \(tab.title)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var closeButtonOpacity: Double {
        if !canClose { return 0.3 }
        return isActive || isHovering ? 1.0 : 0.0
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
