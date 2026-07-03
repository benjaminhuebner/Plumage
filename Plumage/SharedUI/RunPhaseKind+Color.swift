import SwiftUI

// Lives here, not next to RunState, so the ProjectCore domain module stays
// SwiftUI-free.
extension RunState.PhaseKind {
    var color: Color {
        switch self {
        case .running: .green
        case .gate: .orange
        case .failed: .red
        }
    }
}

extension RunHistoryRecord.OutcomeKind {
    var color: Color {
        switch self {
        case .completed: .green
        case .failed: .red
        case .crashed: .orange
        }
    }
}
