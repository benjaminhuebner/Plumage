import SwiftUI

nonisolated enum DragAnimations {
    static let reducedDuration: Double = 0.05

    static func placeholder(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: reducedDuration) : .smooth(duration: 0.18)
    }

    static func drop(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: reducedDuration) : .easeOut(duration: 0.18)
    }

    static func cancel(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: reducedDuration) : .spring(response: 0.3, dampingFraction: 0.7)
    }
}
