import AppKit
import SwiftUI

struct DiffCommenting {
    let file: String
    let model: ReviewFindingsModel
}

struct CommentableDiffLineRow: View {
    let line: Line
    let style: DiffLineStyle
    let anchor: DiffLineAnchor
    let model: ReviewFindingsModel
    var numbers: DiffLineNumber?
    var numberColumnDigits: Int = 0

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiffLineRow(
                line: line, style: style,
                numbers: numbers, numberColumnDigits: numberColumnDigits
            )
            .equatable()
            .overlay {
                if isHovering, model.canComment {
                    Color.accentColor.opacity(0.08)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isHovering, model.canComment {
                    addCommentButton
                }
            }
            .onHover { isHovering = $0 }
            ForEach(rowFindings) { finding in
                DiffCommentRow(finding: finding, model: model)
            }
            if let draft = model.draft, draft.anchor == anchor {
                DiffCommentEditor(model: model)
            }
        }
    }

    private var rowFindings: [ReviewFinding] {
        model.findings(at: anchor).filter { $0.id != model.draft?.editingID }
    }

    private var addCommentButton: some View {
        Button {
            model.beginDraft(at: anchor, lineText: line.content)
        } label: {
            Image(systemName: "plus.bubble.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white, .blue)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, style.horizontalPadding)
        .help("Add review comment")
        .accessibilityLabel("Add review comment on line \(anchor.line)")
    }
}

struct DiffCommentRow: View {
    let finding: ReviewFinding
    let model: ReviewFindingsModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(finding.state == .open ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.comment)
                    .font(.callout)
                    .foregroundStyle(finding.state == .open ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if finding.state == .sent {
                    Text("Sent in round \(finding.round ?? 0)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if finding.state == .open {
                Button("Edit") { model.beginEditing(finding) }
                    .buttonStyle(.link)
                    .font(.caption)
                Button("Delete", role: .destructive) {
                    Task { await model.delete(finding) }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    Color(NSColor.controlBackgroundColor)
                        .opacity(finding.state == .open ? 1 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.25))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct DiffCommentEditor: View {
    let model: ReviewFindingsModel

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Review comment", text: model.draftTextBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...8)
                .focused($isFocused)
                .onAppear { isFocused = true }
            if let message = model.saveErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelDraft() }
                Button(model.draft?.editingID == nil ? "Comment" : "Save") {
                    Task { await model.submitDraft() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(submitDisabled)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.4))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var submitDisabled: Bool {
        (model.draft?.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}
