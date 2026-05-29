import SwiftUI

// Step 1 — grouped project-type selection. Binds the picked `ProjectKind` back
// into the wizard model; the container's "Next" stays disabled until one is set.
struct TypeStepView: View {
    @Bindable var model: NewProjectModel

    var body: some View {
        List(selection: $model.kind) {
            ForEach(ProjectKindGroup.allCases, id: \.self) { group in
                Section(group.displayName) {
                    ForEach(kinds(in: group), id: \.self) { kind in
                        Label(kind.displayName, systemImage: Self.icon(for: kind))
                            .tag(Optional(kind))
                    }
                }
            }
        }
    }

    private func kinds(in group: ProjectKindGroup) -> [ProjectKind] {
        ProjectKind.allCases.filter { $0.group == group }
    }

    private static func icon(for kind: ProjectKind) -> String {
        switch kind {
        case .appleMultiplatform: "apple.logo"
        case .macOS: "macwindow"
        case .iOS: "iphone"
        case .vapor: "drop.fill"
        case .hummingbird: "bird.fill"
        case .swiftCLI: "terminal"
        case .other: "shippingbox"
        }
    }
}
