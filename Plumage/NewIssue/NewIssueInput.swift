import Foundation

@MainActor
@Observable
final class NewIssueInput {
    var title: String = ""
    var slug: String = ""
    var slugTouched: Bool = false
    var type: IssueType = .feature
    var labels: [String] = []
    var labelDraft: String = ""

    func handleTitleChanged() {
        if !slugTouched {
            slug = NextIssueAllocator.slugify(title)
        }
    }

    var slugValid: Bool {
        NextIssueAllocator.isValidSlug(slug)
    }

    var titleValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func collidingFolder(in existingIssues: [DiscoveredIssue]) -> String? {
        guard !slug.isEmpty else { return nil }
        let suffix = "-\(slug)"
        for issue in existingIssues where issue.id.hasSuffix(suffix) {
            return issue.id
        }
        return nil
    }

    func submitEnabled(existingIssues: [DiscoveredIssue]) -> Bool {
        guard titleValid, slugValid else { return false }
        return collidingFolder(in: existingIssues) == nil
    }

    enum SubmitOutcome: Sendable, Equatable {
        case created(URL)
        case collision(folder: String)
        case failed(reason: String)
    }

    func submit(projectURL: URL) async -> SubmitOutcome {
        let allocator = NextIssueAllocator(projectURL: projectURL)
        do {
            let url = try allocator.allocate(
                slug: slug,
                title: title.trimmingCharacters(in: .whitespaces),
                type: type,
                labels: labels
            )
            return .created(url)
        } catch let NextIssueAllocatorError.slugCollision(folder) {
            return .collision(folder: folder)
        } catch let NextIssueAllocatorError.templateMissing(url) {
            return .failed(reason: "Template missing at \(url.path)")
        } catch {
            return .failed(reason: "\(error)")
        }
    }
}
