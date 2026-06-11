import CoreGraphics
import Foundation
import Observation

nonisolated enum DragStatus: Sendable, Equatable {
    case lifting
    case dragging
    case dropping
    case cancelling
}

// Flat properties so Observation invalidates narrowly: a cursor move only
// invalidates cursor/translation readers. A single `state?` struct
// re-evaluated every reader per cursor frame and stalled the gesture.
@Observable
@MainActor
final class DragReorderController<Payload, Target: Equatable> {
    private(set) var isActive: Bool = false
    private(set) var payload: Payload?
    private(set) var sourceID: String?
    private(set) var sourceFrame: CGRect = .zero
    private(set) var cursorLocation: CGPoint = .zero
    private(set) var translation: CGSize = .zero
    private(set) var target: Target?
    private(set) var status: DragStatus = .lifting

    // Owns the post-gesture animation delay; [weak self] in the body lets
    // the Task self-terminate when this controller deallocates without
    // needing a MainActor-isolated deinit.
    private var settleTask: Task<Void, Never>?

    func startLift(payload: Payload, sourceID: String, sourceFrame: CGRect) {
        guard !isActive else { return }
        settleTask?.cancel()
        settleTask = nil
        self.payload = payload
        self.sourceID = sourceID
        self.sourceFrame = sourceFrame
        self.cursorLocation = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        self.translation = .zero
        self.target = nil
        self.status = .lifting
        self.isActive = true
    }

    func updateCursor(location: CGPoint, translation: CGSize) {
        guard isActive else { return }
        self.cursorLocation = location
        self.translation = translation
        if status == .lifting {
            status = .dragging
        }
    }

    func setTarget(_ target: Target?) {
        guard isActive else { return }
        self.target = target
    }

    func beginDrop(finalTranslation: CGSize) {
        guard isActive else { return }
        status = .dropping
        translation = finalTranslation
    }

    func beginCancel() {
        guard isActive else { return }
        status = .cancelling
        translation = .zero
    }

    func clear() {
        settleTask?.cancel()
        settleTask = nil
        isActive = false
        payload = nil
        sourceID = nil
        target = nil
    }

    func scheduleSettle(after duration: Duration) {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }
}
