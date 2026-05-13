import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let arrangement = arrange(subviews: subviews, in: width)
        return CGSize(
            width: width.isFinite ? width : arrangement.bounds.width,
            height: arrangement.bounds.height
        )
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
        var rows: [(start: Int, count: Int, height: CGFloat)] = []
        var rowStart = 0
        var rowCount = 0
        var rowHeight: CGFloat = 0
        var xCursor: CGFloat = 0
        var yCursor: CGFloat = 0
        var maxX: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if xCursor + size.width > width, xCursor > 0 {
                rows.append((rowStart, rowCount, rowHeight))
                rowStart += rowCount
                rowCount = 0
                xCursor = 0
                yCursor += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: xCursor, y: yCursor, width: size.width, height: size.height))
            xCursor += size.width + spacing
            maxX = max(maxX, xCursor)
            rowHeight = max(rowHeight, size.height)
            rowCount += 1
        }
        if rowCount > 0 {
            rows.append((rowStart, rowCount, rowHeight))
        }

        for row in rows {
            for index in row.start..<(row.start + row.count) {
                let dy = (row.height - frames[index].height) / 2
                frames[index] = CGRect(
                    x: frames[index].minX,
                    y: frames[index].minY + dy,
                    width: frames[index].width,
                    height: frames[index].height
                )
            }
        }

        return (frames, CGSize(width: maxX, height: yCursor + rowHeight))
    }
}
