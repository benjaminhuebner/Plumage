import Foundation

nonisolated enum NextIssueAllocatorError: Error, Equatable, Sendable {
    case slugCollision(existingFolder: String)
    case invalidSlug
    case templateMissing(URL)
    case ioFailure(String)
}

nonisolated struct NextIssueAllocator: Sendable {
    let projectURL: URL

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
