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
}
