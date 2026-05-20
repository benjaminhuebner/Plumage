import SwiftUI

struct SidebarSectionHeader: View {
    let title: String
    var help: String?
    var action: (() -> Void)?
    @State private var hovering = false

    init(title: String, action: (() -> Void)? = nil, help: String? = nil) {
        self.title = title
        self.action = action
        self.help = help
    }

    init(title: String, help: String, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.action = action
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.3)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "plus")
                        .imageScale(.small)
                        .foregroundStyle(hovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.5)
                .help(help ?? "")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .listRowSeparator(.hidden)
        .selectionDisabled()
        .contextMenu {
            if let action, let help {
                Button(help, action: action)
            }
        }
    }
}
