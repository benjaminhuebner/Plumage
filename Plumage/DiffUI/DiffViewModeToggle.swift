import SwiftUI

struct DiffViewModeToggle: View {
    @AppStorage(DiffViewMode.storageKey) private var viewMode: DiffViewMode = .unified

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DiffViewMode.allCases) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Image(systemName: mode.symbolName)
                        .imageScale(.medium)
                        .foregroundStyle(viewMode == mode ? Color.accentColor : Color.secondary)
                        .frame(width: 28, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    viewMode == mode
                                        ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mode.helpText)
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(viewMode == mode ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Diff view mode")
    }
}
