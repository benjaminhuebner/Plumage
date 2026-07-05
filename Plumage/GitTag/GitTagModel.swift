import Foundation
import Observation

@MainActor
@Observable
final class GitTagModel {
    let repoURL: URL

    var name: String = ""
    var message: String = ""

    private(set) var existingTags: [String] = []
    private(set) var isWorking = false
    private(set) var error: String?
    private(set) var didFinish = false

    private let creator: any GitTagCreating
    private let lister: GitTagLister

    init(
        repoURL: URL,
        creator: any GitTagCreating = GitTagCreateRunner(),
        lister: GitTagLister = GitTagLister()
    ) {
        self.repoURL = repoURL
        self.creator = creator
        self.lister = lister
    }

    func load() async {
        existingTags = (try? await lister.tags(repoURL: repoURL)) ?? []
    }

    var validationHint: String? {
        Self.tagNameError(name, existing: existingTags)
    }

    var canSubmit: Bool { !isWorking && validationHint == nil }

    nonisolated static func tagNameError(_ name: String, existing: [String]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter a tag name." }
        if !GitBranchName.isSafe(trimmed) { return "That tag name isn't valid." }
        if existing.contains(trimmed) { return "A tag named \"\(trimmed)\" already exists." }
        return nil
    }

    func submit() async {
        guard !isWorking else { return }
        error = nil
        guard validationHint == nil else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await creator.createTag(
                name: name.trimmingCharacters(in: .whitespaces),
                message: message, repoURL: repoURL)
            didFinish = true
        } catch is CancellationError {
        } catch {
            self.error = Self.describe(error, fallback: "Couldn't create the tag.")
        }
    }

    nonisolated static func describe(_ error: any Error, fallback: String) -> String {
        (error as? LocalizedError)?.errorDescription ?? fallback
    }
}
