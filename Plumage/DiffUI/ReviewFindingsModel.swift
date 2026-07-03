import Foundation
import SwiftUI

@MainActor
@Observable
final class ReviewFindingsModel {
    enum Availability: Equatable {
        case loading
        case available
        case unavailable(ReviewFindingsParseError)
    }

    struct Draft: Equatable {
        let anchor: DiffLineAnchor
        let lineText: String
        var text: String
        let editingID: UUID?
    }

    private(set) var availability: Availability = .loading
    private(set) var findings: ReviewFindings = .empty
    var draft: Draft?
    private(set) var saveErrorMessage: String?

    private let findingsURL: URL
    private let clock: @Sendable () -> Date

    init(findingsURL: URL, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.findingsURL = findingsURL
        self.clock = clock
    }

    var canComment: Bool {
        availability == .available
    }

    var openFindings: [ReviewFinding] {
        findings.openFindings
    }

    func load() async {
        let url = findingsURL
        let result = await Task.detached { ReviewFindingsStore.load(from: url) }.value
        switch result {
        case .success(let loaded):
            findings = loaded
            availability = .available
        case .failure(let error):
            availability = .unavailable(error)
        }
    }

    func findings(at anchor: DiffLineAnchor) -> [ReviewFinding] {
        findings.findings.filter {
            $0.file == anchor.file && $0.side == anchor.side && $0.line == anchor.line
        }
    }

    func beginDraft(at anchor: DiffLineAnchor, lineText: String) {
        guard canComment else { return }
        draft = Draft(anchor: anchor, lineText: lineText, text: "", editingID: nil)
    }

    func beginEditing(_ finding: ReviewFinding) {
        guard canComment, finding.state == .open else { return }
        let anchor = DiffLineAnchor(file: finding.file, side: finding.side, line: finding.line)
        draft = Draft(
            anchor: anchor, lineText: finding.lineText, text: finding.comment,
            editingID: finding.id
        )
    }

    func cancelDraft() {
        draft = nil
    }

    var draftTextBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.draft?.text ?? "" },
            set: { [weak self] newValue in self?.draft?.text = newValue }
        )
    }

    func submitDraft() async {
        guard canComment, let draft else { return }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let now = clock()
        var updated = findings
        if let editingID = draft.editingID {
            updated.updateComment(id: editingID, to: text, at: now)
        } else {
            updated.add(
                ReviewFinding(
                    id: UUID(),
                    file: draft.anchor.file,
                    side: draft.anchor.side,
                    line: draft.anchor.line,
                    lineText: draft.lineText,
                    comment: text,
                    state: .open,
                    round: nil,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        if await persist(updated) {
            self.draft = nil
        }
    }

    func delete(_ finding: ReviewFinding) async {
        guard canComment else { return }
        var updated = findings
        updated.remove(id: finding.id)
        _ = await persist(updated)
    }

    @discardableResult
    func markOpenFindingsSent() async -> Bool {
        guard canComment, !findings.openFindings.isEmpty else { return false }
        var updated = findings
        updated.markOpenFindingsSent(round: updated.nextRound, at: clock())
        return await persist(updated)
    }

    @discardableResult
    private func persist(_ updated: ReviewFindings) async -> Bool {
        let url = findingsURL
        do {
            try await Task.detached { try ReviewFindingsStore.save(updated, to: url) }.value
            findings = updated
            saveErrorMessage = nil
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
