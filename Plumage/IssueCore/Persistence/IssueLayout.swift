import Foundation

nonisolated enum IssueLayout {
    // For string-relative path comparisons (routes, run slugs); keep in
    // lockstep with `issuesDirectory`.
    static let issuesRelativePrefix = ".claude/issues/"

    static func issuesDirectory(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(".claude/issues", isDirectory: true)
    }

    static func archiveDirectory(in projectURL: URL) -> URL {
        issuesDirectory(in: projectURL).appendingPathComponent("archive", isDirectory: true)
    }

    static func issueFolder(in projectURL: URL, folderName: String) -> URL {
        issuesDirectory(in: projectURL).appendingPathComponent(folderName, isDirectory: true)
    }

    static func archivedIssueFolder(in projectURL: URL, folderName: String) -> URL {
        archiveDirectory(in: projectURL).appendingPathComponent(folderName, isDirectory: true)
    }

    static func archivedSpecURL(in projectURL: URL, folderName: String) -> URL {
        archivedIssueFolder(in: projectURL, folderName: folderName)
            .appendingPathComponent("spec.md")
    }

    static func specURL(in projectURL: URL, folderName: String) -> URL {
        issueFolder(in: projectURL, folderName: folderName).appendingPathComponent("spec.md")
    }

    static func promptURL(in projectURL: URL, folderName: String) -> URL {
        issueFolder(in: projectURL, folderName: folderName).appendingPathComponent("prompt.md")
    }

    // /plumage-implement writes `PR.md` (uppercase, see SKILL.md). Match the
    // canonical casing so lookups work on case-sensitive volumes.
    static func prURL(in projectURL: URL, folderName: String) -> URL {
        issueFolder(in: projectURL, folderName: folderName).appendingPathComponent("PR.md")
    }

    static func evidenceURL(in projectURL: URL, folderName: String) -> URL {
        issueFolder(in: projectURL, folderName: folderName).appendingPathComponent("evidence.json")
    }

    static func reviewFindingsURL(in projectURL: URL, folderName: String) -> URL {
        issueFolder(in: projectURL, folderName: folderName)
            .appendingPathComponent("review-findings.json")
    }

    static func mergedDiffURL(in projectURL: URL, folderName: String) -> URL {
        issueFolder(in: projectURL, folderName: folderName)
            .appendingPathComponent("merged.diff")
    }

    static func templateURL(in projectURL: URL) -> URL {
        issuesDirectory(in: projectURL).appendingPathComponent("_TEMPLATE.md")
    }

    static func allocationLedgerDirectory(in projectURL: URL) -> URL {
        issuesDirectory(in: projectURL).appendingPathComponent(".allocated", isDirectory: true)
    }

    static func allocationMarkerURL(in projectURL: URL, id: Int) -> URL {
        allocationLedgerDirectory(in: projectURL).appendingPathComponent(String(id), isDirectory: true)
    }
}
