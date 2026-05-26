import SwiftUI

struct PRTabView: View {
    let content: String?

    var body: some View {
        if let content, !content.isEmpty {
            ScrollView {
                renderedMarkdown(content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 240)
        } else {
            BodyTabEmptyState(
                symbol: "doc.text.magnifyingglass",
                title: "No pr.md yet",
                detail:
                    "Created by `/plumage-implement` once the issue moves to `waiting-for-review`."
            )
        }
    }

    // Renders the markdown line-by-line so headings and code fences keep
    // their structure. Inline formatting (bold/italic/links/inline-code)
    // goes through AttributedString(markdown:) — NOT LocalizedStringKey,
    // which would reinterpret `%d`, `%@`, `\(…)` etc. in the user content
    // as format specifiers and mangle the output.
    @ViewBuilder
    private func renderedMarkdown(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks(content).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inlineMarkdown(text))
                .font(headingFont(for: level))
                .padding(.top, level == 1 ? 4 : 6)
        case .paragraph(let text):
            Text(Self.inlineMarkdown(text))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(Self.inlineMarkdown(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .codeBlock(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .blank:
            Color.clear.frame(height: 4)
        }
    }

    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title.weight(.bold)
        case 2: return .title2.weight(.semibold)
        case 3: return .title3.weight(.semibold)
        default: return .headline
        }
    }

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case codeBlock(String)
        case blank
    }

    private func parseBlocks(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                var fenceLines: [String] = []
                index += 1
                while index < lines.count, !lines[index].hasPrefix("```") {
                    fenceLines.append(lines[index])
                    index += 1
                }
                blocks.append(.codeBlock(fenceLines.joined(separator: "\n")))
                if index < lines.count { index += 1 }
                continue
            }
            if line.isEmpty {
                blocks.append(.blank)
            } else if let heading = matchHeading(line) {
                blocks.append(heading)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                blocks.append(.paragraph(line))
            }
            index += 1
        }
        return blocks
    }

    private func matchHeading(_ line: String) -> MarkdownBlock? {
        var level = 0
        for char in line {
            guard char == "#" else { break }
            level += 1
        }
        guard level >= 1, level <= 6, line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " "
        else {
            return nil
        }
        let text = line.dropFirst(level + 1).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }
}
