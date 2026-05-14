import Foundation

nonisolated enum NextIssueAllocatorError: Error, Equatable, Sendable {
    case slugCollision(existingFolder: String)
    case invalidSlug
    case templateMissing(URL)
    case ioFailure(String)
}

nonisolated struct NextIssueAllocator: Sendable {
    let projectURL: URL

    private var fileManager: FileManager { .default }

    func allocate(
        slug: String,
        title: String,
        type: IssueType,
        labels: [String],
        now: Date = .now
    ) throws -> URL {
        guard Self.isValidSlug(slug) else { throw NextIssueAllocatorError.invalidSlug }

        if let collision = findCollidingFolder(slug: slug) {
            throw NextIssueAllocatorError.slugCollision(existingFolder: collision)
        }

        let highest = highestExistingID()
        let nextID = highest + 1
        let padding = paddingWidth()
        let padded = Self.paddedID(nextID, padding: padding)

        let templateURL = IssueLayout.templateURL(in: projectURL)
        guard let templateData = fileManager.contents(atPath: templateURL.path),
            let template = String(data: templateData, encoding: .utf8)
        else {
            throw NextIssueAllocatorError.templateMissing(templateURL)
        }

        let created = Self.iso8601(from: now)
        let rendered = Self.substituteTemplate(
            template,
            id: nextID,
            idPadded: padded,
            title: title,
            slug: slug,
            created: created,
            type: type,
            labels: labels
        )

        let folderName = "\(padded)-\(slug)"
        let folderURL = IssueLayout.issueFolder(in: projectURL, folderName: folderName)
        let specURL = IssueLayout.specURL(in: projectURL, folderName: folderName)

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            guard let data = rendered.data(using: .utf8) else {
                throw NextIssueAllocatorError.ioFailure("could not encode spec as UTF-8")
            }
            try data.write(to: specURL, options: .atomic)
        } catch let error as NextIssueAllocatorError {
            throw error
        } catch {
            throw NextIssueAllocatorError.ioFailure(error.localizedDescription)
        }
        return specURL
    }

    private func findCollidingFolder(slug: String) -> String? {
        let issuesDir = IssueLayout.issuesDirectory(in: projectURL)
        let archiveDir = IssueLayout.archiveDirectory(in: projectURL)
        for dir in [issuesDir, archiveDir] {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in entries where name.hasSuffix("-\(slug)") {
                let parts = IssueDiscovery.extractID(fromFolderName: name)
                if parts.id != nil && parts.slug == slug { return name }
            }
        }
        return nil
    }

    private func highestExistingID() -> Int {
        let issuesDir = IssueLayout.issuesDirectory(in: projectURL)
        guard
            let enumerator = fileManager.enumerator(
                at: issuesDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return 0 }
        var maxID = 0
        for case let url as URL in enumerator where url.lastPathComponent == "spec.md" {
            guard let data = fileManager.contents(atPath: url.path),
                let text = String(data: data, encoding: .utf8)
            else { continue }
            if let id = Self.extractIDFromFrontmatter(text) {
                maxID = max(maxID, id)
            }
        }
        return maxID
    }

    private static func extractIDFromFrontmatter(_ text: String) -> Int? {
        var sawOpener = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if sawOpener { return nil }
                sawOpener = true
                continue
            }
            if !sawOpener { continue }
            if trimmed.hasPrefix("id:") {
                let value = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    private func paddingWidth() -> Int {
        let configured = (try? ConfigLoader.load(at: projectURL))?.issueIdPadding ?? 5
        return max(configured, 1)
    }

    private static func iso8601(from date: Date) -> String {
        // Allocate per-call: ISO8601DateFormatter is not documented as
        // thread-safe by Apple. See notes.md.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func slugify(_ input: String) -> String {
        let lowered = input.lowercased()
        let replaced = lowered.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            if value >= 0x61 && value <= 0x7A { return Character(scalar) }
            if value >= 0x30 && value <= 0x39 { return Character(scalar) }
            return "-"
        }
        let collapsed = String(replaced).split(separator: "-", omittingEmptySubsequences: true)
        return collapsed.joined(separator: "-")
    }

    static func paddedID(_ id: Int, padding: Int) -> String {
        let digits = String(id)
        let width = max(padding, digits.count)
        return String(repeating: "0", count: width - digits.count) + digits
    }

    static func isValidSlug(_ input: String) -> Bool {
        guard let first = input.unicodeScalars.first else { return false }
        if !isSlugAlphanumeric(first) { return false }
        for scalar in input.unicodeScalars.dropFirst() {
            if !isSlugAlphanumeric(scalar) && scalar != "-" { return false }
        }
        return true
    }

    private static func isSlugAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value >= 0x61 && value <= 0x7A { return true }
        if value >= 0x30 && value <= 0x39 { return true }
        return false
    }

    static func substituteTemplate(
        _ template: String,
        id: Int,
        idPadded: String,
        title: String,
        slug: String,
        created: String,
        type: IssueType,
        labels: [String]
    ) -> String {
        var out = template
        out = out.replacingOccurrences(of: "<<<ID>>>", with: String(id))
        out = out.replacingOccurrences(of: "<<<ID_PADDED>>>", with: idPadded)
        out = out.replacingOccurrences(of: "<<<TITLE>>>", with: title)
        out = out.replacingOccurrences(of: "<<<SLUG>>>", with: slug)
        out = out.replacingOccurrences(of: "<<<CREATED>>>", with: created)
        return injectTypeAndLabels(out, type: type, labels: labels)
    }

    private static func injectTypeAndLabels(
        _ rendered: String,
        type: IssueType,
        labels: [String]
    ) -> String {
        var lines = rendered.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for index in lines.indices {
            if lines[index] == "type: feature" {
                lines[index] = "type: \(type.rawValue)"
            }
            if lines[index] == "labels: []" {
                lines[index] = "labels: [\(labels.joined(separator: ", "))]"
            }
        }
        return lines.joined(separator: "\n")
    }
}
