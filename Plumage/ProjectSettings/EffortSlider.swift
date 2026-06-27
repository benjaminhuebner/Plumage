import SwiftUI

struct EffortSlider: View {
    @Binding var choice: EffortLevel
    let stops: [EffortLevel]
    var mixed: Bool = false
    let accessibilityLabel: String

    private var activeIndex: Int {
        stops.firstIndex(of: choice) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 3) {
                markerRow
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(height: 1)
                labelsRow
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let step = geo.size.width / CGFloat(stops.count)
                    let index = min(stops.count - 1, max(0, Int(value.location.x / step)))
                    if stops[index] != choice { choice = stops[index] }
                }
            )
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(mixed ? "Mixed" : choice.displayName)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                choice = stops[min(stops.count - 1, activeIndex + 1)]
            case .decrement:
                choice = stops[max(0, activeIndex - 1)]
            @unknown default:
                break
            }
        }
    }

    private var markerRow: some View {
        ZStack {
            if mixed {
                Text("Mixed")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    ForEach(stops.indices, id: \.self) { index in
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.accentColor)
                            .opacity(index == activeIndex ? 1 : 0)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: 11)
    }

    private var labelsRow: some View {
        HStack(spacing: 0) {
            ForEach(stops.indices, id: \.self) { index in
                let isActive = !mixed && index == activeIndex
                Text(label(for: stops[index]))
                    .font(.caption)
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundStyle(
                        isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func label(for level: EffortLevel) -> String {
        switch level {
        case .default: "default"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .xhigh: "xhigh"
        case .max: "max"
        case .ultracode: "ultracode"
        }
    }
}

#Preview {
    @Previewable @State var choice: EffortLevel = .ultracode
    EffortSlider(
        choice: $choice,
        stops: ModelChoice.opus.supportedEfforts,
        accessibilityLabel: "Preview effort"
    )
    .frame(width: ModelEffortColumns.effort)
    .padding()
}
