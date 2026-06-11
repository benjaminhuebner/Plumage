import AppKit
import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("WorkflowCommandSerialization")
struct WorkflowCommandSerializationTests {
    @Test("plain string with no placeholders round-trips identical")
    func plainRoundTrip() {
        let original = "/plumage-plan abcdef"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        let back = WorkflowCommandSerialization.string(from: attributed)
        #expect(back == original)
    }

    @Test("placeholders get replaced by attachment cells")
    func placeholdersToChips() {
        let original = "/cmd <slug>\n<prompt>\n<spec>"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)

        // Count NSTextAttachment runs by scanning the attachment attribute.
        var attachmentCount = 0
        attributed.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            if value is NSTextAttachment { attachmentCount += 1 }
        }
        #expect(attachmentCount == 3)
    }

    @Test("attributedString -> string -> attributedString round-trips")
    func fullRoundTrip() {
        let original = "/my-plan <slug> --inline\n<prompt>\n<spec>"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        let back = WorkflowCommandSerialization.string(from: attributed)
        #expect(back == original)
    }

    @Test("unknown <token> stays as literal text")
    func unknownTokenStays() {
        let original = "echo <unknown-token>"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        let back = WorkflowCommandSerialization.string(from: attributed)
        #expect(back == original)
        // No attachment runs.
        var attachmentCount = 0
        attributed.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            if value is NSTextAttachment { attachmentCount += 1 }
        }
        #expect(attachmentCount == 0)
    }

    @Test("attachment cells round-trip placeholder identity")
    func cellsCarryPlaceholder() {
        let original = "<slug>"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        let attachment =
            attributed.attribute(
                .attachment, at: 0, effectiveRange: nil
            ) as? NSTextAttachment
        let cell = attachment?.attachmentCell as? WorkflowCommandPlaceholderCell
        #expect(cell?.placeholder == .slug)
    }

    @Test("string copy preserves order across multi-line and tokens")
    func multiLineOrder() {
        let original = "A <slug>\nB <prompt>\nC"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        let back = WorkflowCommandSerialization.string(from: attributed)
        #expect(back == original)
    }

    // MARK: - #if/#end directives

    private func attachmentCells(in attributed: NSAttributedString) -> [NSTextAttachmentCell] {
        var cells: [NSTextAttachmentCell] = []
        attributed.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            if let attachment = value as? NSTextAttachment,
                let cell = attachment.attachmentCell as? NSTextAttachmentCell
            {
                cells.append(cell)
            }
        }
        return cells
    }

    @Test("valid directive lines become attachment cells and round-trip literally")
    func directiveRoundTrip() {
        let original = "#if chore spike\n/quick <slug>\n#else\n/fallback\n#end\n/shared"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        let cells = attachmentCells(in: attributed)
        #expect(cells.compactMap { $0 as? WorkflowCommandDirectiveCell }.count == 3)
        #expect(cells.compactMap { $0 as? WorkflowCommandPlaceholderCell }.count == 1)
        #expect(WorkflowCommandSerialization.string(from: attributed) == original)
    }

    @Test("#else renders as a neutral badge cell")
    func elseBadge() {
        let attributed = WorkflowCommandSerialization.attributedString(from: "#else")
        let cell = attachmentCells(in: attributed).first as? WorkflowCommandDirectiveCell
        guard case .elseBranch = cell?.kind else {
            Issue.record("expected an else directive cell")
            return
        }
        #expect(cell?.rawText == "#else")
    }

    @Test("directive cell carries parsed types in listed order")
    func directiveCellTypes() {
        let attributed = WorkflowCommandSerialization.attributedString(from: "#if spike chore")
        let cell = attachmentCells(in: attributed).first as? WorkflowCommandDirectiveCell
        guard case .open(let types) = cell?.kind else {
            Issue.record("expected an open directive cell")
            return
        }
        #expect(types == [.spike, .chore])
    }

    @Test("unknown type token keeps the whole line as plain text")
    func directiveUnknownTokenStaysPlain() {
        for original in [
            "#if foobar", "#if chore foobar", "#if", "#ifx chore", "#end junk", "#else junk",
            "#elsewhere",
        ] {
            let attributed = WorkflowCommandSerialization.attributedString(from: original)
            #expect(
                attachmentCells(in: attributed).isEmpty,
                "\(original) must not become an attachment"
            )
            #expect(WorkflowCommandSerialization.string(from: attributed) == original)
        }
    }

    @Test("leading and trailing whitespace around a directive stays plain text")
    func directiveWhitespacePreserved() {
        let original = "  #if chore  \n/cmd"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        #expect(attachmentCells(in: attributed).count == 1)
        #expect(WorkflowCommandSerialization.string(from: attributed) == original)
    }

    @Test("directive must own its line — inline #if stays plain text")
    func inlineDirectiveStaysPlain() {
        let original = "/cmd #if chore"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        #expect(attachmentCells(in: attributed).isEmpty)
        #expect(WorkflowCommandSerialization.string(from: attributed) == original)
    }

    @Test("interior whitespace inside a directive round-trips byte-identically")
    func directiveInteriorWhitespace() {
        let original = "#if\tchore  spike"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        #expect(attachmentCells(in: attributed).count == 1)
        #expect(WorkflowCommandSerialization.string(from: attributed) == original)
    }

    @Test("mixed placeholder and directive content round-trips")
    func mixedContentRoundTrip() {
        let original = "/plan <slug> - <prompt>\n#if feature refactor\n<spec>\n#end\n#if chore\n/lean"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        let back = WorkflowCommandSerialization.string(from: attributed)
        #expect(back == original)
    }

    // MARK: - Slash-command highlighting

    private func foregroundColor(in attributed: NSAttributedString, at index: Int) -> NSColor? {
        attributed.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    @Test("leading slash command gets the accent color, arguments stay plain")
    func commandTokenHighlighted() {
        let attributed = WorkflowCommandSerialization.attributedString(from: "/plumage-plan abc")
        #expect(foregroundColor(in: attributed, at: 0) == .controlAccentColor)
        #expect(foregroundColor(in: attributed, at: 12) == .controlAccentColor)
        #expect(foregroundColor(in: attributed, at: 14) == .labelColor)
    }

    @Test("every line highlights its own leading command")
    func perLineHighlighting() {
        let original = "/first\nplain text\n/second arg"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        let nsOriginal = original as NSString
        #expect(foregroundColor(in: attributed, at: 0) == .controlAccentColor)
        #expect(
            foregroundColor(in: attributed, at: nsOriginal.range(of: "plain").location)
                == .labelColor
        )
        #expect(
            foregroundColor(in: attributed, at: nsOriginal.range(of: "/second").location)
                == .controlAccentColor
        )
    }

    @Test("a slash mid-line is not a command token")
    func midLineSlashNotHighlighted() {
        let attributed = WorkflowCommandSerialization.attributedString(from: "echo a/b")
        for index in 0..<attributed.length {
            #expect(foregroundColor(in: attributed, at: index) == .labelColor)
        }
    }
}
