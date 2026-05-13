import SwiftUI

struct LabelChip: View {
    private let text: String
    private let backgroundColor: Color

    init(text: String) {
        self.text = text
        self.backgroundColor = LabelColor.color(for: text)
    }

    private init(text: String, color: Color) {
        self.text = text
        self.backgroundColor = color
    }

    static func overflow(count: Int) -> LabelChip {
        LabelChip(text: "+\(count)", color: Color(NSColor.tertiarySystemFill))
    }

    var body: some View {
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
    }
    .padding()
}
