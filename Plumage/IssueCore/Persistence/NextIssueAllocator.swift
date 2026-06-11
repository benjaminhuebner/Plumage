import Foundation
import os

nonisolated enum NextIssueAllocatorError: Error, Equatable, Sendable {
    case slugCollision(existingFolder: String)
    case invalidSlug
    case templateMissing(URL)
    case ioFailure(String)
    case reservationExhausted(URL)
}

// LocalizedError conformance so SwiftUI's Alert / `error.localizedDescription`
// surfaces a usable message instead of the generic NSError bridge ("…error 0.").
extension NextIssueAllocatorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .slugCollision(let folder):
            return "An issue with this slug already exists: \(folder). Choose a different title."
        case .invalidSlug:
            return
                "Title produces no valid slug after normalization. At least one letter or digit is required."
        case .templateMissing(let url):
            return "_TEMPLATE.md is missing at \(url.path)."
        case .ioFailure(let reason):
            return "Failed to create issue: \(reason)"
        case .reservationExhausted(let ledger):
            return "Could not reserve an issue ID after 64 attempts. Inspect the ledger at \(ledger.path)."
        }
    }
}

nonisolated struct NextIssueAllocator: Sendable {
    let projectURL: URL

    private var fileManager: FileManager { .default }

    private static let logger = Logger(subsystem: "com.plumage", category: "NextIssueAllocator")

    func allocate(
        slug: String,
        title: String,
        type: IssueType,
        labels: [String],
        prompt: String,
        now: Date = .now
    ) throws -> URL {
        guard Self.isValidSlug(slug) else { throw NextIssueAllocatorError.invalidSlug }

        if let collision = findCollidingFolder(slug: slug) {
            throw NextIssueAllocatorError.slugCollision(existingFolder: collision)
        }

        // Read the template before reserving: markers are permanent, so a
        // deterministic, user-fixable failure must not burn an ID per retry.
        let templateURL = IssueLayout.templateURL(in: projectURL)
        guard let templateData = fileManager.contents(atPath: templateURL.path),
            let template = String(data: templateData, encoding: .utf8)
        else {
            throw NextIssueAllocatorError.templateMissing(templateURL)
        }

        let nextID = try reserveNextID()
        let padding = paddingWidth()
        let padded = Self.paddedID(nextID, padding: padding)

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
        let promptURL = IssueLayout.promptURL(in: projectURL, folderName: folderName)

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            guard let data = rendered.data(using: .utf8) else {
                throw NextIssueAllocatorError.ioFailure("could not encode spec as UTF-8")
            }
            try data.write(to: specURL, options: .atomic)
            // Empty prompt → write 0-byte file deliberately so every issue
            // folder has the same shape (spec.md + prompt.md).
            let promptData = prompt.data(using: .utf8) ?? Data()
            try promptData.write(to: promptURL, options: .atomic)
        } catch let error as NextIssueAllocatorError {
            throw error
        } catch {
            throw NextIssueAllocatorError.ioFailure(error.localizedDescription)
        }
        return specURL
    }

    private func reserveNextID() throws -> Int {
        let ledger = IssueLayout.allocationLedgerDirectory(in: projectURL)
        do {
            try fileManager.createDirectory(at: ledger, withIntermediateDirectories: true)
        } catch {
            throw NextIssueAllocatorError.ioFailure(error.localizedDescription)
        }
        return try reserveID(above: max(highestExistingID(), highestReservedID()))
    }

    // Atomic mkdir is the compare-and-swap: a parallel session losing the race
    // gets fileWriteFileExists and retries one higher. Markers stay forever.
    func reserveID(above highest: Int) throws -> Int {
        var highest = highest
        for _ in 0..<64 {
            let candidate = highest + 1
            let marker = IssueLayout.allocationMarkerURL(in: projectURL, id: candidate)
            do {
                try fileManager.createDirectory(at: marker, withIntermediateDirectories: false)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                highest = candidate
            } catch {
                throw NextIssueAllocatorError.ioFailure(error.localizedDescription)
            }
        }
        throw NextIssueAllocatorError.reservationExhausted(
            IssueLayout.allocationLedgerDirectory(in: projectURL))
    }

    private func highestReservedID() -> Int {
        let ledger = IssueLayout.allocationLedgerDirectory(in: projectURL)
        // highestExistingID's enumerator skips hidden dirs, so .allocated needs its own scan.
        guard let entries = try? fileManager.contentsOfDirectory(atPath: ledger.path) else {
            return 0
        }
        return entries.compactMap(Int.init).max() ?? 0
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
        // Read IDs from folder names (e.g. "00042-foo") instead of opening
        // each spec.md and parsing its frontmatter. The padded-prefix is the
        // canonical source — IssueDiscovery uses the same path — so the
        // scan no longer pays a per-issue disk-read on a hot create flow.
        // Recursive enumeration still merges active + archive subtrees
        // (the tests pin this with active/archive parameter cases).
        guard
            let enumerator = fileManager.enumerator(
                at: issuesDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { url, error in
                    Self.logger.error(
                        "highestExistingID: enumeration error at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    return true
                }
            )
        else { return 0 }
        var maxID = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let parts = IssueDiscovery.extractID(fromFolderName: url.lastPathComponent)
            if let id = parts.id {
                maxID = max(maxID, id)
            }
        }
        return maxID
    }

    private func paddingWidth() -> Int {
        let configured = (try? ConfigLoader.load(at: projectURL))?.issueIdPadding ?? 5
        return max(configured, 1)
    }

    private static func iso8601(from date: Date) -> String {
        ISO8601Flexible.string(from: date)
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
        // YAML-quote the user-supplied title so `:`, `[`, `{`, `#`, leading
        // dashes, or embedded newlines don't produce a frontmatter file
        // that fails its own re-parse (red "invalid" card). Routes the
        // value through the same formatter the form-commit path uses.
        out = out.replacingOccurrences(of: "<<<TITLE>>>", with: FrontmatterMutator.formatTitleValue(title))
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
                // Same quoting as the edit path — raw joining produced
                // invalid YAML (red card) for labels containing `:` or `#`.
                lines[index] = "labels: \(FrontmatterMutator.formatLabels(labels))"
            }
        }
        return lines.joined(separator: "\n")
    }
}
