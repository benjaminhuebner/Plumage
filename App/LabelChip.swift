import SwiftUI

struct LabelChip: View {
    private let text: String
    private let backgroundColor: Color
    private let onRemove: (() -> Void)?

    init(text: String) {
        self.text = text
        self.backgroundColor = LabelColor.color(for: text)
        self.onRemove = nil
    }

    init(text: String, onRemove: @escaping () -> Void) {
        self.text = text
        self.backgroundColor = LabelColor.color(for: text)
        self.onRemove = onRemove
    }

    private init(text: String, color: Color) {
        self.text = text
        self.backgroundColor = color
        self.onRemove = nil
    }

    static func overflow(count: Int) -> LabelChip {
        LabelChip(text: "+\(count)", color: Color(NSColor.tertiarySystemFill))
    }

    var body: some View {
        if let onRemove {
            HStack(spacing: 4) {
                Text(text)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(text)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
        } else {
            Text(text)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(backgroundColor, in: Capsule())
                .frame(maxWidth: 80, alignment: .leading)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 4) {
            LabelChip(text: "feature")
            LabelChip(text: "chore")
            LabelChip(text: "v0.1")
            LabelChip(text: "bootstrap")
        }
        HStack(spacing: 4) {
            LabelChip(text: "ui")
            LabelChip(text: "backend")
            LabelChip(text: "perf")
            LabelChip(text: "this-name-is-quite-long-and-will-truncate")
        }
        HStack(spacing: 4) {
            LabelChip(text: "feature")
            LabelChip(text: "chore")
            LabelChip(text: "v0.1")
            LabelChip(text: "bootstrap")
            LabelChip.overflow(count: 3)
        }
        HStack(spacing: 4) {
            LabelChip(text: "feature", onRemove: {})
            LabelChip(text: "v0.1", onRemove: {})
            LabelChip(text: "bootstrap", onRemove: {})
        }
    }
    .padding()
}
