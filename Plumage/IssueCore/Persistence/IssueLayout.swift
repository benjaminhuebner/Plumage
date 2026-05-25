import Foundation

nonisolated enum IssueLayout {
    static func issuesDirectory(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(".claude/issues", isDirectory: true)
    }

    static func archiveDirectory(in projectURL: URL) -> URL {
        issuesDirectory(in: projectURL).appendingPathComponent("archive", isDirectory: true)
    }

    static func issueFolder(in projectURL: URL, folderName: String) -> URL {
        issuesDirectory(in: projectURL).appendingPathComponent(folderName, isDirectory: true)
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

    static func templateURL(in projectURL: URL) -> URL {
        issuesDirectory(in: projectURL).appendingPathComponent("_TEMPLATE.md")
    }
}
