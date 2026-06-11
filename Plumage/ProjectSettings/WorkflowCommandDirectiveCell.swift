import AppKit
import SwiftUI

// rawText keeps the literal directive so round-trips stay byte-identical.
// @unchecked Sendable for the same reason as WorkflowCommandPlaceholderCell:
// state is set once at init, NSTextAttachmentCell itself is not Sendable.
final class WorkflowCommandDirectiveCell: NSTextAttachmentCell, @unchecked Sendable {
    nonisolated enum Kind {
        case open(types: [IssueType])
        case elseBranch
        case end

        var badgeLabel: String {
            switch self {
            case .open: "if"
            case .elseBranch: "else"
            case .end: "end"
            }
        }
    }

    let kind: Kind
    let rawText: String
    // Resolved on the main actor at init (IssueType's color extensions are
    // MainActor-isolated) because TextKit may invoke draw/cellSize off-main.
    private let segments: [Segment]

    nonisolated static let horizontalPadding: CGFloat = 6
    nonisolated static let verticalPadding: CGFloat = 2
    nonisolated static let cornerRadius: CGFloat = 5
    nonisolated static let segmentSpacing: CGFloat = 4
    nonisolated static let baselineOffset: CGFloat = -2

    @MainActor
    init(kind: Kind, rawText: String) {
        self.kind = kind
        self.rawText = rawText
        self.segments = Self.makeSegments(for: kind)
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private struct Segment {
        let label: String
        let fill: NSColor
        let stroke: NSColor?
        let textColor: NSColor
    }

    @MainActor
    private static func makeSegments(for kind: Kind) -> [Segment] {
        let badge = Segment(
            label: kind.badgeLabel,
            fill: NSColor.secondaryLabelColor.withAlphaComponent(0.15),
            stroke: NSColor.secondaryLabelColor.withAlphaComponent(0.4),
            textColor: .secondaryLabelColor
        )
        switch kind {
        case .open(let types):
            return [badge]
                + types.map { type in
                    Segment(
                        label: type.rawValue,
                        fill: NSColor(type.color),
                        stroke: nil,
                        textColor: NSColor(type.foregroundOnTint)
                    )
                }
        case .elseBranch, .end:
            return [badge]
        }
    }

    nonisolated override func cellSize() -> NSSize {
        let attrs = Self.textAttributes()
        var width: CGFloat = 0
        var height: CGFloat = 0
        let all = segments
        for segment in all {
            let labelSize = (segment.label as NSString).size(withAttributes: attrs)
            width += ceil(labelSize.width) + Self.horizontalPadding * 2
            height = max(height, ceil(labelSize.height) + Self.verticalPadding * 2)
        }
        width += Self.segmentSpacing * CGFloat(max(0, all.count - 1))
        return NSSize(width: width, height: height)
    }

    nonisolated override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: Self.baselineOffset)
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        let attrs = Self.textAttributes()
        var cursorX = cellFrame.minX
        for segment in segments {
            let labelSize = (segment.label as NSString).size(withAttributes: attrs)
            let segmentWidth = ceil(labelSize.width) + Self.horizontalPadding * 2
            let segmentRect = NSRect(
                x: cursorX,
                y: cellFrame.minY,
                width: segmentWidth,
                height: cellFrame.height
            )
            let path = NSBezierPath(
                roundedRect: segmentRect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: Self.cornerRadius,
                yRadius: Self.cornerRadius
            )
            segment.fill.setFill()
            path.fill()
            if let stroke = segment.stroke {
                stroke.setStroke()
                path.lineWidth = 0.75
                path.stroke()
            }

            var labelAttrs = attrs
            labelAttrs[.foregroundColor] = segment.textColor
            let textRect = NSRect(
                x: segmentRect.minX + Self.horizontalPadding,
                y: segmentRect.minY + (segmentRect.height - labelSize.height) / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            (segment.label as NSString).draw(in: textRect, withAttributes: labelAttrs)
            cursorX += segmentWidth + Self.segmentSpacing
        }
    }

    nonisolated private static func textAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        ]
    }
}
