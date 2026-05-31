import SwiftUI

// Step 1 — pick a template. A grid of framed-icon tiles, grouped under section
// headers (Apple Apps / Server-side / Other), mirroring the Xcode template
// chooser. Binds the picked `ProjectKind` back into the wizard model; the
// container's "Next" stays disabled until one is set. No `.glassEffect` — these
// are content-surface tiles, not navigation chrome (Liquid-Glass rule).
struct TypeStepView: View {
    @Bindable var model: NewProjectModel

    private static let columns = [GridItem(.adaptive(minimum: 132), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(ProjectKindGroup.allCases, id: \.self) { group in
                    let kinds = kinds(in: group)
                    if !kinds.isEmpty {
                        Section {
                            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 16) {
                                ForEach(kinds, id: \.self) { kind in
                                    tile(for: kind)
                                }
                            }
                        } header: {
                            Text(group.displayName)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func tile(for kind: ProjectKind) -> some View {
        let isSelected = model.kind == kind
        return Button {
            model.kind = kind
        } label: {
            VStack(spacing: 10) {
                Image(systemName: Self.icon(for: kind))
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.quaternary.opacity(0.6))
                    )
                Text(kind.displayName)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
