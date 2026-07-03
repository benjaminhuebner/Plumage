import SwiftUI

// Row visuals and small components shared by the unified (DiffLineViews) and
// side-by-side renderers so the two stay in lockstep.

extension LineKind {
    var diffSymbol: String {
        switch self {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        }
    }

    var diffSymbolColor: Color {
        switch self {
        case .added: return .green
        case .removed: return .red
        case .context: return .secondary
        }
    }

    var diffRowTint: Color {
        switch self {
        case .added: return Color.green.opacity(0.10)
        case .removed: return Color.red.opacity(0.10)
        case .context: return Color.clear
        }
    }
}

enum DiffRowAccent {
    static var hover: Color { Color.accentColor.opacity(0.08) }
}

extension DiffCommenting {
    // Equality for the commenting-aware Equatable hunk views. Skips findings
    // content: changes invalidate rows via @Observable tracking.
    static func isSame(_ lhs: DiffCommenting?, _ rhs: DiffCommenting?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let left?, let right?):
            return left.file == right.file && left.model === right.model
        default:
            return false
        }
    }
}

struct DiffAddCommentButton: View {
    let anchor: DiffLineAnchor
    let line: Line
    let model: ReviewFindingsModel
    var iconSize: CGFloat = 15
    var frameSize: CGSize = CGSize(width: 24, height: 24)

    var body: some View {
        Button {
            model.beginDraft(at: anchor, lineText: line.content)
        } label: {
            Image(systemName: "plus.bubble.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(.white, .blue)
                .frame(width: frameSize.width, height: frameSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add review comment")
        .accessibilityLabel("Add review comment on line \(anchor.line)")
    }
}

struct DiffNoNewlineMarker: View {
    let style: DiffLineStyle

    var body: some View {
        Text(#"\ No newline at end of file"#)
            .font(style.font)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, 1)
    }
}

struct DiffModeChangeLabel: View {
    let modeChange: ModeChange

    var body: some View {
        Text("\(modeChange.old) → \(modeChange.new)")
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
    }
}
