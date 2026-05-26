import Foundation
import Testing

@testable import Plumage

@Suite("NextIssueAllocator pure helpers")
struct NextIssueAllocatorPureTests {
    @Test(
        "slugify lowercases, replaces non-alnum with hyphen, collapses, trims",
        arguments: [
            ("Add Labels Support", "add-labels-support"),
            ("Über—User_Auth", "ber-user-auth"),
            ("---foo bar---", "foo-bar"),
            ("", ""),
            ("Already-kebab-case", "already-kebab-case"),
            ("UPPER", "upper"),
            ("a b   c", "a-b-c"),
            ("123 Numbers", "123-numbers"),
        ]
    )
    func slugifyCases(input: String, expected: String) {
        #expect(NextIssueAllocator.slugify(input) == expected)
    }

    @Test(
        "paddedID zero-pads up to width and grows beyond",
        arguments: [
            (7, 5, "00007"),
            (100_000, 5, "100000"),
            (1, 3, "001"),
        ]
    )
    func paddedIDCases(id: Int, padding: Int, expected: String) {
        #expect(NextIssueAllocator.paddedID(id, padding: padding) == expected)
    }

    @Test(
        "isValidSlug accepts kebab and rejects everything else",
        arguments: [
            ("foo", true),
            ("foo-bar", true),
            ("a", true),
            ("00007-foo", true),
            ("1foo", true),
            ("", false),
            ("-foo", false),
            ("Foo", false),
            ("foo_bar", false),
            ("foo bar", false),
        ]
    )
    func slugValidationCases(input: String, expected: Bool) {
        #expect(NextIssueAllocator.isValidSlug(input) == expected)
    }

    @Test("substituteTemplate replaces all markers and injects type and labels")
    func substituteTemplateFull() {
        let template = """
            ---
            id: <<<ID>>>
            title: <<<TITLE>>>
            type: feature
            status: draft
            created: <<<CREATED>>>
            updated: <<<CREATED>>>
            branch: issue/<<<ID_PADDED>>>-<<<SLUG>>>
            labels: []
            model: null
            ---

            # Issue <<<ID_PADDED>>>: <<<TITLE>>>
            """

        let rendered = NextIssueAllocator.substituteTemplate(
            template,
            id: 2,
            idPadded: "00002",
            title: "Bar",
            slug: "bar",
            created: "2026-05-13T07:00:00Z",
            type: .chore,
            labels: ["chore", "v0.1"]
        )

        #expect(rendered.contains("id: 2\n"))
        #expect(rendered.contains("title: Bar\n"))
        #expect(rendered.contains("type: chore\n"))
        #expect(rendered.contains("labels: [chore, v0.1]\n"))
        #expect(rendered.contains("branch: issue/00002-bar\n"))
        #expect(rendered.contains("created: 2026-05-13T07:00:00Z\n"))
        #expect(rendered.contains("# Issue 00002: Bar"))
        #expect(!rendered.contains("<<<"))
    }

    @Test("substituteTemplate keeps feature type when type is .feature and empty labels stay empty")
    func substituteTemplateDefaults() {
        let template = """
            type: feature
            labels: []
            """
        let rendered = NextIssueAllocator.substituteTemplate(
            template,
            id: 1,
            idPadded: "00001",
            title: "T",
            slug: "t",
            created: "x",
            type: .feature,
            labels: []
        )
        #expect(rendered.contains("type: feature"))
        #expect(rendered.contains("labels: []"))
    }
}

@Suite("NextIssueAllocatorError descriptions")
struct NextIssueAllocatorErrorDescriptionTests {
    @Test("slugCollision description names the existing folder")
    func slugCollisionDescription() {
        let error = NextIssueAllocatorError.slugCollision(existingFolder: "00042-foo")
        let description = error.localizedDescription
        #expect(description.contains("00042-foo"))
        #expect(description.contains("already exists"))
        #expect(!description.contains("error 0"))
    }

    @Test("invalidSlug description hints at the cause")
    func invalidSlugDescription() {
        let description = NextIssueAllocatorError.invalidSlug.localizedDescription
        #expect(description.contains("slug"))
        #expect(!description.contains("error 1"))
    }

    @Test("templateMissing description includes the path")
    func templateMissingDescription() {
        let url = URL(fileURLWithPath: "/tmp/proj/.claude/issues/_TEMPLATE.md")
        let description = NextIssueAllocatorError.templateMissing(url).localizedDescription
        #expect(description.contains("/tmp/proj/.claude/issues/_TEMPLATE.md"))
        #expect(description.contains("_TEMPLATE.md"))
        #expect(!description.contains("error 2"))
    }

    @Test("ioFailure description surfaces the underlying reason")
    func ioFailureDescription() {
        let description = NextIssueAllocatorError.ioFailure("disk full").localizedDescription
        #expect(description.contains("disk full"))
        #expect(!description.contains("error 3"))
    }
}

@Suite("NextIssueAllocator.allocate")
struct NextIssueAllocatorAllocateTests {
    @Test("allocates next ID, writes spec with type/labels, returns spec URL")
    func happyPath() throws {
        let fixture = try Fixture()
        try fixture.writeTemplate()
        try fixture.writeConfig(padding: 5)
        try fixture.writeSpec(folder: "00001-foo", id: 1)

        let allocator = NextIssueAllocator(projectURL: fixture.root)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-13T07:00:00Z"))
        let url = try allocator.allocate(
            slug: "bar", title: "Bar", type: .chore, labels: ["chore", "v0.1"], now: now
        )

        #expect(url.path.hasSuffix(".claude/issues/00002-bar/spec.md"))
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("id: 2\n"))
        #expect(content.contains("title: Bar\n"))
        #expect(content.contains("type: chore\n"))
        #expect(content.contains("status: draft\n"))
        #expect(content.contains("branch: issue/00002-bar\n"))
        #expect(content.contains("labels: [chore, v0.1]\n"))
        #expect(content.contains("created: 2026-05-13T07:00:00Z\n"))
        #expect(content.contains("updated: 2026-05-13T07:00:00Z\n"))
    }

    @Test("active collision throws .slugCollision and writes nothing")
    func collisionActive() throws {
        let fixture = try Fixture()
        try fixture.writeTemplate()
        try fixture.writeSpec(folder: "00001-foo", id: 1)

        let allocator = NextIssueAllocator(projectURL: fixture.root)
        #expect(throws: NextIssueAllocatorError.slugCollision(existingFolder: "00001-foo")) {
            try allocator.allocate(slug: "foo", title: "X", type: .feature, labels: [])
        }
        let issuesDir = fixture.root.appendingPathComponent(".claude/issues")
        let entries = try FileManager.default.contentsOfDirectory(atPath: issuesDir.path).sorted()
        #expect(entries == ["00001-foo", "_TEMPLATE.md"])
    }

    @Test("archive collision throws .slugCollision")
    func collisionArchive() throws {
        let fixture = try Fixture()
        try fixture.writeTemplate()
        try fixture.writeSpec(folder: "archive/00001-foo", id: 1)

        let allocator = NextIssueAllocator(projectURL: fixture.root)
        #expect(throws: NextIssueAllocatorError.slugCollision(existingFolder: "00001-foo")) {
            try allocator.allocate(slug: "foo", title: "X", type: .feature, labels: [])
        }
    }

    @Test("empty repo creates the folder and starts at ID 1")
    func emptyRepo() throws {
        let fixture = try Fixture(prepareIssuesDir: false)
        try fixture.writeTemplate(at: fixture.root.appendingPathComponent(".claude/issues/_TEMPLATE.md"))

        let allocator = NextIssueAllocator(projectURL: fixture.root)
        let url = try allocator.allocate(
            slug: "bar", title: "Bar", type: .feature, labels: [])
        #expect(url.path.hasSuffix(".claude/issues/00001-bar/spec.md"))
    }

    @Test("invalid slug throws .invalidSlug as defense-in-depth")
    func invalidSlug() throws {
        let fixture = try Fixture()
        try fixture.writeTemplate()
        let allocator = NextIssueAllocator(projectURL: fixture.root)
        #expect(throws: NextIssueAllocatorError.invalidSlug) {
            try allocator.allocate(slug: "Foo Bar", title: "X", type: .feature, labels: [])
        }
    }

    @Test("padding grows organically when next ID exceeds configured width")
    func paddingGrows() throws {
        let fixture = try Fixture()
        try fixture.writeTemplate()
        try fixture.writeConfig(padding: 3)
        try fixture.writeSpec(folder: "999-foo", id: 999)

        let allocator = NextIssueAllocator(projectURL: fixture.root)
        let url = try allocator.allocate(
            slug: "bar", title: "Bar", type: .feature, labels: [])
        #expect(url.path.hasSuffix(".claude/issues/1000-bar/spec.md"))
    }

    @Test("missing _TEMPLATE.md throws .templateMissing")
    func templateMissing() throws {
        let fixture = try Fixture()
        let allocator = NextIssueAllocator(projectURL: fixture.root)
        do {
            _ = try allocator.allocate(
                slug: "bar", title: "X", type: .feature, labels: [])
            Issue.record("expected throw")
        } catch let NextIssueAllocatorError.templateMissing(url) {
            #expect(url.lastPathComponent == "_TEMPLATE.md")
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("ID search includes archive folders")
    func idFromArchive() throws {
        let fixture = try Fixture()
        try fixture.writeTemplate()
        try fixture.writeSpec(folder: "archive/00005-foo", id: 5)

        let allocator = NextIssueAllocator(projectURL: fixture.root)
        let url = try allocator.allocate(
            slug: "bar", title: "Bar", type: .feature, labels: [])
        #expect(url.path.hasSuffix(".claude/issues/00006-bar/spec.md"))
    }

    // Pins archive-aware highest-ID behavior across active/archive mixes. The
    // recursive enumerator on .claude/issues/ already walks into archive/,
    // but tying the contract down with parameterized cases protects against
    // accidental rewrites (e.g., switching to non-recursive contentsOfDirectory).
    @Test(
        "highestExistingID merges active and archive folders",
        arguments: [
            // (active ids, archive ids, expected next id)
            ([Int](), [Int](), 1),
            ([3], [Int](), 4),
            ([Int](), [7], 8),
            ([3, 5], [Int](), 6),
            ([Int](), [4, 8], 9),
            ([5], [7], 8),  // archive beats active
            ([12], [4], 13),  // active beats archive
            ([3, 9], [4, 11], 12),
        ]
    )
    func highestIDMergesActiveAndArchive(
        active: [Int], archive: [Int], expectedNext: Int
    ) throws {
        let fixture = try Fixture()
        try fixture.writeTemplate()
        for id in active {
            try fixture.writeSpec(folder: "\(String(format: "%05d", id))-active", id: id)
        }
        for id in archive {
            try fixture.writeSpec(folder: "archive/\(String(format: "%05d", id))-archived", id: id)
        }

        let allocator = NextIssueAllocator(projectURL: fixture.root)
        let url = try allocator.allocate(
            slug: "next", title: "Next", type: .feature, labels: [])
        let expectedPadded = String(format: "%05d", expectedNext)
        #expect(url.path.hasSuffix(".claude/issues/\(expectedPadded)-next/spec.md"))
    }
}

private struct Fixture {
    let root: URL

    init(prepareIssuesDir: Bool = true) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageNextIssueAllocator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.root = tmp
        if prepareIssuesDir {
            try FileManager.default.createDirectory(
                at: tmp.appendingPathComponent(".claude/issues"),
                withIntermediateDirectories: true
            )
        }
    }

    func writeTemplate(at url: URL? = nil) throws {
        let target =
            url
            ?? root.appendingPathComponent(".claude/issues/_TEMPLATE.md")
        let body = """
            ---
            id: <<<ID>>>
            title: <<<TITLE>>>
            type: feature
            status: draft
            created: <<<CREATED>>>
            updated: <<<CREATED>>>
            branch: issue/<<<ID_PADDED>>>-<<<SLUG>>>
            labels: []
            model: null
            ---

            # Issue <<<ID_PADDED>>>: <<<TITLE>>>
            """
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try body.write(to: target, atomically: true, encoding: .utf8)
    }

    func writeConfig(padding: Int) throws {
        let bundle = root.appendingPathComponent("Test.plumage")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let json = """
            {
              "name": "Test",
              "schemaVersion": 1,
              "issueIdPadding": \(padding)
            }
            """
        try json.write(
            to: bundle.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    }

    func writeSpec(folder: String, id: Int) throws {
        let dir = root.appendingPathComponent(".claude/issues/\(folder)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = """
            ---
            id: \(id)
            title: T
            type: feature
            status: draft
            created: 2026-01-01T00:00:00Z
            updated: 2026-01-01T00:00:00Z
            branch: issue/\(folder)
            labels: []
            model: null
            ---
            """
        try body.write(
            to: dir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
    }
}
