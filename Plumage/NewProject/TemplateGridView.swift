import SwiftUI

// Shared project-kind picker grid. Extracted from `TypeStepView` so the New
// Project and Migrate Project flows present an identical selection surface.
struct TemplateGridView: View {
    @Binding var selectedKind: ProjectKind?

    private static let columns = [GridItem(.adaptive(minimum: 116), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ProjectKindGroup.allCases, id: \.self) { group in
                    let kinds = kinds(in: group)
                    if !kinds.isEmpty {
                        Section {
                            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 12) {
                                ForEach(kinds, id: \.self) { kind in
                                    tile(for: kind)
                                }
                            }
                        } header: {
                            Text(group.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func tile(for kind: ProjectKind) -> some View {
        let isSelected = selectedKind == kind
        return Button {
            selectedKind = kind
        } label: {
            VStack(spacing: 8) {
                Image(systemName: Self.icon(for: kind))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.quaternary.opacity(0.6))
                    )
                Text(kind.displayName)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
