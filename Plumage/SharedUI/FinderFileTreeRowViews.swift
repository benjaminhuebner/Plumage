import AppKit
import SwiftUI

enum FinderFileTreeDropRole: Equatable {
    case none
    case target(extendsBelow: Bool)
    case member(isLast: Bool)
}

// The stock drop-on feedback is a hairline ring that reads as a glitch —
// replace it with the Xcode-navigator look: a full accent fill on the target
// folder row plus a light wash over its visible children, one rounded region.
final class FinderFileTreeRowView: NSTableRowView {
    var dropRole: FinderFileTreeDropRole = .none {
        didSet {
            guard oldValue != dropRole else { return }
            needsDisplay = true
            // The accent fill is a dark surface in any appearance — flip the
            // hosted SwiftUI row to dark so its text reads white on it.
            let isTarget = if case .target = dropRole { true } else { false }
            for subview in subviews {
                subview.appearance = isTarget ? NSAppearance(named: .darkAqua) : nil
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        dropRole = .none
    }

    // Drawing is driven entirely by `dropRole` (the coordinator knows the
    // whole target region); the stock per-row feedback must stay silent.
    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {}

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        let inset = bounds.insetBy(dx: 6, dy: 0)
        switch dropRole {
        case .none:
            return
        case .target(let extendsBelow):
            let rect =
                extendsBelow
                ? NSRect(x: inset.minX, y: 0, width: inset.width, height: bounds.height)
                : inset.insetBy(dx: 0, dy: 1)
            NSColor.controlAccentColor.setFill()
            Self.roundedPath(
                rect, topRadius: 6, bottomRadius: extendsBelow ? 0 : 6
            ).fill()
        case .member(let isLast):
            let rect = NSRect(
                x: inset.minX, y: 0, width: inset.width,
                height: isLast ? bounds.height - 1 : bounds.height)
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            Self.roundedPath(rect, topRadius: 0, bottomRadius: isLast ? 6 : 0).fill()
        }
    }

    // NSBezierPath has no per-corner radii — the target region needs square
    // edges where it meets the member rows below it.
    private static func roundedPath(
        _ rect: NSRect, topRadius: CGFloat, bottomRadius: CGFloat
    ) -> NSBezierPath {
        let path = NSBezierPath()
        // Flipped view: minY = top edge on screen.
        let topLeft = NSPoint(x: rect.minX, y: rect.minY)
        let topRight = NSPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = NSPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = NSPoint(x: rect.minX, y: rect.maxY)
        path.move(to: NSPoint(x: rect.minX, y: rect.minY + topRadius))
        path.appendArc(from: topLeft, to: topRight, radius: topRadius)
        path.appendArc(from: topRight, to: bottomRight, radius: topRadius)
        path.appendArc(from: bottomRight, to: bottomLeft, radius: bottomRadius)
        path.appendArc(from: bottomLeft, to: topLeft, radius: bottomRadius)
        path.close()
        return path
    }
}

// One hosting view per cell, reused via `rootView` swap — rebuilding the
// SwiftUI hierarchy on every reuse causes scroll jank.
final class FinderFileTreeCellView: NSTableCellView {
    private let hosting: NSHostingView<AnyView>

    init(identifier: NSUserInterfaceItemIdentifier) {
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        self.identifier = identifier
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ view: AnyView) {
        hosting.rootView = view
    }
}
