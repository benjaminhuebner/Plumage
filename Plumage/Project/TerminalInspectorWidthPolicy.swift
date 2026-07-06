import CoreGraphics

// Caps the terminal inspector relative to the window: an absolute-width sash
// range let the inspector crush the detail column (unreadable status bar) and
// push claude's TUI past the window edge on narrow windows.
nonisolated enum TerminalInspectorWidthPolicy {
    static let absoluteMax: CGFloat = 900
    static let absoluteMin: CGFloat = 280
    static let preferredMin: CGFloat = 360
    static let preferredIdeal: CGFloat = 480
    static let windowFraction: CGFloat = 0.55
    // The sidebar reserve applies even while the sidebar is hidden: a
    // visibility-dependent cap re-squeezes the inspector mid sidebar
    // animation — two racing column animations read as jank.
    static let detailReserve: CGFloat = 360
    static let sidebarReserve: CGFloat = 240

    static func maxWidth(forContentWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return absoluteMax }
        let available = width - detailReserve - sidebarReserve
        let capped = min(width * windowFraction, available)
        return min(absoluteMax, max(absoluteMin, capped))
    }

    static func minWidth(forContentWidth width: CGFloat) -> CGFloat {
        min(preferredMin, maxWidth(forContentWidth: width))
    }

    static func idealWidth(forContentWidth width: CGFloat) -> CGFloat {
        min(preferredIdeal, maxWidth(forContentWidth: width))
    }

    // Live window resize reports every pixel; snapping to a coarse grid keeps
    // the @State (and the window body re-render) to one write per 16pt step.
    static func quantizedContentWidth(_ width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return (width / 16).rounded(.down) * 16
    }
}
