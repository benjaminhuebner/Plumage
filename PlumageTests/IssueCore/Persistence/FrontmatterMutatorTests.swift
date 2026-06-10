import Foundation
import Testing

@testable import Plumage

@Suite("FrontmatterMutator.transform")
struct FrontmatterMutatorTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let nowISO = "2025-06-15T15:06:40Z"

    @Test("status-only mutation rewrites status, stamps updated, preserves order line absent")
    func statusOnly() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: .inProgress,
            newOrder: .keep,
            now: now
        )
        #expect(output.contains("status: in-progress"))
        #expect(output.contains("updated: \(nowISO)"))
        #expect(!output.contains("order:"))
        #expect(output.contains("# Body"))
    }

    @Test("order-only insertion adds order line after status")
    func orderOnlyInsert() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: nil,
            newOrder: .set(5.5),
            now: now
        )
        let lines = output.components(separatedBy: "\n")
        let statusIdx = try #require(lines.firstIndex { $0.hasPrefix("status:") })
        let nextLine = lines[statusIdx + 1]
        #expect(nextLine == "order: 5.5")
        #expect(output.contains("status: approved"))
    }

    @Test("status+order replaces both, integer order formatted without trailing zero")
    func statusAndOrder() throws {
        let input = baseSpec(status: "approved", order: "12")
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: .done,
            newOrder: .set(7.0),
            now: now
        )
        #expect(output.contains("status: done"))
        #expect(output.contains("order: 7"))
        #expect(!output.contains("order: 7.0"))
    }

    @Test("fractional order survives at full precision (no %g rounding)")
    func orderFullPrecision() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: nil,
            newOrder: .set(1234.5678),
            now: now
        )
        #expect(output.contains("order: 1234.5678"))
    }

    @Test("title with newline is escaped into quoted YAML")
    func titleNewlineEscaped() {
        #expect(FrontmatterMutator.formatTitleValue("a\nb") == #""a\nb""#)
    }

    @Test("order .set(nil) removes the order line")
    func orderRemove() throws {
        let input = baseSpec(status: "approved", order: "3.5")
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: nil,
            newOrder: .set(nil),
            now: now
        )
        #expect(!output.contains("order:"))
    }

    @Test("preserves comments, blank lines, and body bit-exact")
    func preservesEverythingElse() throws {
        let input = """
            ---
            id: 1
            title: Spec
            type: feature
            status: approved
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00001-x
            labels: [a, b]
            model: null
            ---

            # Body

            Some line.

            ---

            More body.

            Another paragraph.
            """
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: .inProgress,
            newOrder: .keep,
            now: now
        )
        let bodyMarker = try #require(output.range(of: "\n---\n"))
        let body = output[bodyMarker.upperBound...]
        let openRange = try #require(input.range(of: "---\n"))
        let closeRange = try #require(
            input.range(of: "\n---\n", range: openRange.upperBound..<input.endIndex)
        )
        let inputBody = input[closeRange.upperBound...]
        #expect(body == inputBody)
    }

    @Test("updated line is rewritten to now in ISO-8601 UTC")
    func updatedStamped() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: .done,
            newOrder: .keep,
            now: now
        )
        #expect(output.contains("updated: \(nowISO)"))
        #expect(!output.contains("updated: 2026-05-12T10:00:00Z"))
    }

    @Test("missing frontmatter throws noFrontmatter")
    func missingFrontmatter() {
        let input = "# No frontmatter here\n\nSome text."
        #expect(throws: MutatorError.noFrontmatter) {
            try FrontmatterMutator.transform(
                content: input,
                newStatus: .approved,
                newOrder: .keep,
                now: now
            )
        }
    }

    @Test("missing closing delimiter throws noFrontmatter")
    func missingClosingDelimiter() {
        let input = """
            ---
            id: 1
            status: approved
            """
        #expect(throws: MutatorError.noFrontmatter) {
            try FrontmatterMutator.transform(
                content: input,
                newStatus: .done,
                newOrder: .keep,
                now: now
            )
        }
    }

    @Test("body triple-dash is not treated as second frontmatter delimiter")
    func bodyTripleDashIgnored() throws {
        let input = """
            ---
            id: 1
            title: t
            type: feature
            status: approved
            created: 2026-05-12T09:00:00Z
            updated: 2026-05-12T10:00:00Z
            branch: issue/00001-x
            labels: []
            model: null
            ---

            # Body

            ---

            Body still here.
            """
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: .done,
            newOrder: .keep,
            now: now
        )
        #expect(output.contains("status: done"))
        #expect(output.contains("Body still here."))
        // The body `---` should remain in place.
        let allDashLines = output.components(separatedBy: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }
        #expect(allDashLines.count == 3)
    }

    @Test("mutate(specURL:) reads, transforms, and writes back")
    func mutateRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrontmatterMutatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let specURL = tmpDir.appendingPathComponent("spec.md")
        try baseSpec(status: "approved").write(to: specURL, atomically: true, encoding: .utf8)

        try FrontmatterMutator.mutate(
            specURL: specURL,
            newStatus: .inProgress,
            newOrder: .set(2.5),
            now: now
        )

        let written = try String(contentsOf: specURL, encoding: .utf8)
        #expect(written.contains("status: in-progress"))
        #expect(written.contains("order: 2.5"))
        #expect(written.contains("updated: \(nowISO)"))
    }

    @Test("nil newStatus leaves status untouched")
    func nilStatusLeavesUnchanged() throws {
        let input = baseSpec(status: "blocked")
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: nil,
            newOrder: .set(1.0),
            now: now
        )
        #expect(output.contains("status: blocked"))
        #expect(output.contains("order: 1"))
    }

    @Test("title-only mutation rewrites title and stamps updated")
    func titleOnly() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(title: .set("New Title")),
            now: now
        )
        #expect(output.contains("title: New Title"))
        #expect(output.contains("status: approved"))
        #expect(output.contains("updated: \(nowISO)"))
    }

    @Test("type-only mutation rewrites type using rawValue")
    func typeOnly() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(type: .set(.chore)),
            now: now
        )
        #expect(output.contains("type: chore"))
        #expect(!output.contains("type: feature"))
    }

    @Test("labels-only mutation rewrites labels in flow style")
    func labelsOnly() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(labels: .set(["ui", "ux"])),
            now: now
        )
        #expect(output.contains("labels: [ui, ux]"))
    }

    @Test("labels mutation with empty array writes empty flow-style list")
    func labelsEmpty() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(labels: .set([])),
            now: now
        )
        #expect(output.contains("labels: []"))
    }

    @Test("multi-field mutation applies title + type + status + labels in one call")
    func multiField() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(
                title: .set("Bigger UI"),
                type: .set(.spike),
                status: .set(.inProgress),
                labels: .set(["ui", "v0.1"])
            ),
            now: now
        )
        #expect(output.contains("title: Bigger UI"))
        #expect(output.contains("type: spike"))
        #expect(output.contains("status: in-progress"))
        #expect(output.contains("labels: [ui, v0.1]"))
        #expect(output.contains("updated: \(nowISO)"))
    }

    @Test("title with colon gets double-quoted")
    func titleSpecialColon() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(title: .set("Foo: Bar")),
            now: now
        )
        #expect(output.contains("title: \"Foo: Bar\""))
    }

    @Test("title with hash gets double-quoted")
    func titleSpecialHash() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(title: .set("Issue #42")),
            now: now
        )
        #expect(output.contains("title: \"Issue #42\""))
    }

    @Test("title with embedded double-quote escapes the quote")
    func titleSpecialQuote() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(title: .set(#"Say "hi""#)),
            now: now
        )
        #expect(output.contains(#"title: "Say \"hi\"""#))
    }

    @Test("label containing colon gets quoted")
    func labelSpecialColon() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(labels: .set(["a:b", "ok"])),
            now: now
        )
        #expect(output.contains("labels: [\"a:b\", ok]"))
    }

    @Test("missing title field with title.set throws noFrontmatter")
    func missingTitleFieldThrows() {
        let input = """
            ---
            id: 1
            status: approved
            ---
            body
            """
        #expect(throws: MutatorError.noFrontmatter) {
            try FrontmatterMutator.transform(
                content: input,
                mutation: FrontmatterMutation(title: .set("X")),
                now: now
            )
        }
    }

    @Test("body .set replaces body and stamps updated in a single pass")
    func bodySetReplacesBody() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(body: .set("Brand new body.")),
            now: now
        )
        #expect(output.contains("Brand new body."))
        #expect(!output.contains("Some content."))
        #expect(!output.contains("# Body"))
        #expect(output.contains("updated: \(nowISO)"))
        // Frontmatter delimiter still intact.
        let dashLines = output.components(separatedBy: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }
        #expect(dashLines.count == 2)
    }

    @Test("body .set combined with frontmatter fields produces one rewrite")
    func bodySetCombinedWithFields() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            mutation: FrontmatterMutation(
                status: .set(.done),
                body: .set("Done now.")
            ),
            now: now
        )
        #expect(output.contains("status: done"))
        #expect(output.contains("Done now."))
        #expect(output.contains("updated: \(nowISO)"))
    }

    @Test("legacy mutate(specURL:newStatus:newOrder:) wrapper still works")
    func legacyWrapper() throws {
        let input = baseSpec(status: "approved")
        let output = try FrontmatterMutator.transform(
            content: input,
            newStatus: .done,
            newOrder: .set(2.0),
            now: now
        )
        #expect(output.contains("status: done"))
        #expect(output.contains("order: 2"))
    }

    private func baseSpec(status: String, order: String? = nil) -> String {
        var lines = [
            "---",
            "id: 1",
            "title: Sample",
            "type: feature",
            "status: \(status)",
            "created: 2026-05-12T09:00:00Z",
            "updated: 2026-05-12T10:00:00Z",
            "branch: issue/00001-x",
            "labels: []",
            "model: null",
        ]
        if let order { lines.append("order: \(order)") }
        lines.append("---")
        lines.append("")
        lines.append("# Body")
        lines.append("")
        lines.append("Some content.")
        return lines.joined(separator: "\n")
    }
}
