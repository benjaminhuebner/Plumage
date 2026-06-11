import AppKit

// Rounded-pill NSTextAttachmentCell that renders a placeholder token
// (<slug>, <prompt>, <spec>) as a single atomic glyph in the NSTextView.
// Backspace deletes the whole pill because the cell occupies a single
// attachment-character slot in the text storage.
//
// All methods stay nonisolated because NSTextAttachmentCell's overridable
// surface is nonisolated and TextKit may invoke layout off the main actor.
// @unchecked Sendable: instances aren't actually shared mutably (cell state
// is set once at init and never written again), but NSTextAttachmentCell
// itself is not Sendable so we vouch for it.
final class WorkflowCommandPlaceholderCell: NSTextAttachmentCell, @unchecked Sendable {
    let placeholder: WorkflowPlaceholder

    nonisolated static let horizontalPadding: CGFloat = 6
    nonisolated static let verticalPadding: CGFloat = 2
    nonisolated static let cornerRadius: CGFloat = 5
    nonisolated static let baselineOffset: CGFloat = -2

    init(placeholder: WorkflowPlaceholder) {
        self.placeholder = placeholder
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    nonisolated override func cellSize() -> NSSize {
        let attrs = Self.textAttributes()
        let labelSize = (placeholder.token as NSString).size(withAttributes: attrs)
        return NSSize(
            width: ceil(labelSize.width) + Self.horizontalPadding * 2,
            height: ceil(labelSize.height) + Self.verticalPadding * 2
        )
    }

    nonisolated override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: Self.baselineOffset)
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        let path = NSBezierPath(
            roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        )
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 0.75
        path.stroke()

        var attrs = Self.textAttributes()
        attrs[.foregroundColor] =
            NSColor.controlAccentColor.blended(
                withFraction: 0.4, of: .labelColor
            ) ?? NSColor.labelColor
        let labelSize = (placeholder.token as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: cellFrame.minX + Self.horizontalPadding,
            y: cellFrame.minY + (cellFrame.height - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        (placeholder.token as NSString).draw(in: textRect, withAttributes: attrs)
    }

    nonisolated private static func textAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        ]
    }
}

// Pure data conversion between String (with `<slug>`/`<prompt>`/`<spec>` tokens)
// and NSAttributedString (chip-rendered). The string side is fully nonisolated;
// the attributedString side touches NSFont/NSColor for default attributes, so
// it stays @MainActor.
enum WorkflowCommandSerialization {
    // Regex matches the three known placeholders only. Unknown tokens like
    // `<xyz>` stay as literal text so a user-typed `<3` doesn't get eaten.
    // Static pattern is a compile-time-constant regex; force-unwrap is the
    // documented idiom for "this can never fail because the literal is valid".
    // Internal so the editor's typing-time auto-conversion path can reuse the
    // same regex without re-allocating one per keystroke.
    nonisolated static let placeholderPattern: NSRegularExpression = {
        let raw = "<(slug|prompt|spec)>"
        guard let regex = try? NSRegularExpression(pattern: raw, options: []) else {
            preconditionFailure("Invariant: placeholder regex must compile")
        }
        return regex
    }()

    // Group 1 excludes the line's leading/trailing whitespace so that stays
    // plain text; `#end junk`/`#else junk` deliberately don't match here.
    nonisolated static let directivePattern: NSRegularExpression = {
        let raw = "^[ \\t]*(#if(?:[ \\t]+[^ \\t\\r\\n]+)+|#else|#end)[ \\t]*$"
        guard
            let regex = try? NSRegularExpression(pattern: raw, options: [.anchorsMatchLines])
        else {
            preconditionFailure("Invariant: directive regex must compile")
        }
        return regex
    }()

    // U+FFFC (attachment char) is excluded so a chip glued to a slash command
    // doesn't get swallowed into the highlighted token.
    nonisolated static let lineCommandPattern: NSRegularExpression = {
        let raw = "^(/[^\\s\\x{FFFC}]+)"
        guard
            let regex = try? NSRegularExpression(pattern: raw, options: [.anchorsMatchLines])
        else {
            preconditionFailure("Invariant: line command regex must compile")
        }
        return regex
    }()

    // Re-applied wholesale on every change: the reset pass clears highlights
    // on lines that stopped matching (e.g. the leading `/` was deleted).
    @MainActor
    static func applyCommandHighlighting(to storage: NSMutableAttributedString) {
        let plain = storage.string
        let fullRange = NSRange(location: 0, length: (plain as NSString).length)
        guard fullRange.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        storage.addAttribute(
            .font,
            value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            range: fullRange
        )
        lineCommandPattern.enumerateMatches(in: plain, options: [], range: fullRange) {
            match, _, _ in
            guard let match else { return }
            storage.addAttribute(
                .foregroundColor, value: NSColor.controlAccentColor, range: match.range
            )
            storage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                range: match.range
            )
        }
    }

    // nil when any `#if` token is not a known issue type — the whole line
    // then stays plain text, which is the user's typo signal.
    nonisolated static func directiveKind(
        for text: String
    ) -> WorkflowCommandDirectiveCell.Kind? {
        guard let directive = WorkflowCommandDirective.parse(line: text) else { return nil }
        switch directive {
        case .open(let tokens):
            guard !tokens.isEmpty else { return nil }
            let types = tokens.compactMap(IssueType.init(rawValue:))
            guard types.count == tokens.count else { return nil }
            return .open(types: types)
        case .elseBranch:
            return .elseBranch
        case .end:
            return .end
        }
    }

    @MainActor
    static func attributedString(from raw: String) -> NSAttributedString {
        let nsRaw = raw as NSString
        let fullRange = NSRange(location: 0, length: nsRaw.length)
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]

        struct Replacement {
            let range: NSRange
            let attachment: NSTextAttachment
        }
        var replacements: [Replacement] = []

        placeholderPattern.enumerateMatches(in: raw, options: [], range: fullRange) {
            match, _, _ in
            guard let match else { return }
            let placeholderRaw = nsRaw.substring(with: match.range(at: 1))
            guard let placeholder = WorkflowPlaceholder(rawValue: placeholderRaw) else {
                return
            }
            let attachment = NSTextAttachment()
            attachment.attachmentCell = WorkflowCommandPlaceholderCell(placeholder: placeholder)
            replacements.append(Replacement(range: match.range, attachment: attachment))
        }
        directivePattern.enumerateMatches(in: raw, options: [], range: fullRange) {
            match, _, _ in
            guard let match else { return }
            let textRange = match.range(at: 1)
            let text = nsRaw.substring(with: textRange)
            guard let kind = directiveKind(for: text) else { return }
            let attachment = NSTextAttachment()
            attachment.attachmentCell = WorkflowCommandDirectiveCell(kind: kind, rawText: text)
            replacements.append(Replacement(range: textRange, attachment: attachment))
        }
        replacements.sort { $0.range.location < $1.range.location }

        let result = NSMutableAttributedString()
        var cursor = 0
        for replacement in replacements {
            if replacement.range.location > cursor {
                let pre = nsRaw.substring(
                    with: NSRange(
                        location: cursor,
                        length: replacement.range.location - cursor
                    )
                )
                result.append(NSAttributedString(string: pre, attributes: defaultAttrs))
            }
            result.append(NSAttributedString(attachment: replacement.attachment))
            cursor = replacement.range.location + replacement.range.length
        }
        if cursor < nsRaw.length {
            let tail = nsRaw.substring(
                with: NSRange(location: cursor, length: nsRaw.length - cursor)
            )
            result.append(NSAttributedString(string: tail, attributes: defaultAttrs))
        }
        applyCommandHighlighting(to: result)
        return result
    }

    nonisolated static func string(from attributed: NSAttributedString) -> String {
        var output = ""
        let length = attributed.length
        let nsString = attributed.string as NSString
        var index = 0
        while index < length {
            var range = NSRange()
            if let attachment = attributed.attribute(
                .attachment, at: index, effectiveRange: &range
            ) as? NSTextAttachment {
                if let cell = attachment.attachmentCell as? WorkflowCommandPlaceholderCell {
                    output.append(cell.placeholder.token)
                } else if let cell = attachment.attachmentCell as? WorkflowCommandDirectiveCell {
                    output.append(cell.rawText)
                } else if let object = attachment.fileWrapper?.preferredFilename {
                    output.append(object)
                }
                index = range.location + range.length
                continue
            }
            // Non-attachment run: scan forward while no attachment is present.
            var runRange = NSRange()
            _ = attributed.attribute(.attachment, at: index, effectiveRange: &runRange)
            let stop = min(runRange.location + runRange.length, length)
            output.append(
                nsString.substring(with: NSRange(location: index, length: stop - index))
            )
            index = stop
        }
        return output
    }
}
