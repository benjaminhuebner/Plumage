import SwiftUI

nonisolated enum LabelTagInputLogic {
    static func commit(draft: inout String, into labels: inout [String]) {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        defer { draft = "" }
        guard !trimmed.isEmpty else { return }
        if !labels.contains(trimmed) {
            labels.append(trimmed)
        }
    }

    static func handleDraftChange(
        new: String,
        draft: inout String,
        labels: inout [String]
    ) {
        if new.contains(",") {
            let parts = new.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            for token in parts.dropLast() {
                var tmp = token
                commit(draft: &tmp, into: &labels)
            }
            draft = parts.last ?? ""
        } else {
            draft = new
        }
    }

    static func handleBackspaceOnEmptyDraft(draft: String, labels: inout [String]) {
        guard draft.isEmpty, !labels.isEmpty else { return }
        labels.removeLast()
    }
}

struct LabelTagInput: View {
    @Binding var labels: [String]
    @Binding var draft: String

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                LabelChip(text: label) {
                    labels.remove(at: index)
                }
            }
            TextField(
                "Add label",
                text: Binding(
                    get: { draft },
                    set: { new in
                        LabelTagInputLogic.handleDraftChange(
                            new: new, draft: &draft, labels: &labels)
                    }
                )
            )
            .textFieldStyle(.plain)
            .frame(minWidth: 80)
            .onSubmit {
                LabelTagInputLogic.commit(draft: &draft, into: &labels)
            }
            .onKeyPress(.delete) {
                if draft.isEmpty {
                    LabelTagInputLogic.handleBackspaceOnEmptyDraft(
                        draft: draft, labels: &labels)
                    return .handled
                }
                return .ignored
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let arrangement = arrange(subviews: subviews, in: width)
        return CGSize(width: width.isFinite ? width : arrangement.bounds.width, height: arrangement.bounds.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let arrangement = arrange(subviews: subviews, in: bounds.width)
        for (index, frame) in arrangement.frames.enumerated() {
            let origin = CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY)
            subviews[index].place(
                at: origin, proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrange(
        subviews: Subviews, in width: CGFloat
    )
        -> (frames: [CGRect], bounds: CGSize)
    {
        var frames: [CGRect] = []
        var rowHeight: CGFloat = 0
        var xCursor: CGFloat = 0
        var yCursor: CGFloat = 0
        var maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if xCursor + size.width > width, xCursor > 0 {
                xCursor = 0
                yCursor += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: xCursor, y: yCursor, width: size.width, height: size.height))
            xCursor += size.width + spacing
            maxX = max(maxX, xCursor)
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, CGSize(width: maxX, height: yCursor + rowHeight))
    }
}

#Preview {
    @Previewable @State var labels: [String] = ["feature", "v0.1", "bootstrap"]
    @Previewable @State var draft: String = ""
    LabelTagInput(labels: $labels, draft: $draft)
        .padding()
        .frame(width: 360)
}
