import SwiftUI

struct DiffFindingsSummary: View {
    let model: ReviewFindingsModel
    let files: [FileDiff]
    let onJump: (DiffLineAnchor) -> Void

    @State private var isExpanded = true

    var body: some View {
        switch model.availability {
        case .loading:
            EmptyView()
        case .unavailable(let error):
            Label(
                "Review comments unavailable — \(error.summary)",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        case .available:
            if !model.findings.findings.isEmpty {
                summary
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sortedOpen) { finding in
                        row(finding)
                    }
                    ForEach(sortedSent) { finding in
                        row(finding)
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack(spacing: 8) {
                    Text("Review comments")
                        .font(.callout.weight(.semibold))
                    Text("\(model.openFindings.count) open")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            Divider()
        }
    }

    private var sortedOpen: [ReviewFinding] {
        model.findings.openFindings.sorted(by: anchorOrder)
    }

    private var sortedSent: [ReviewFinding] {
        model.findings.sentFindings.sorted { lhs, rhs in
            let leftRound = lhs.round ?? 0
            let rightRound = rhs.round ?? 0
            if leftRound != rightRound { return leftRound > rightRound }
            return anchorOrder(lhs, rhs)
        }
    }

    private func anchorOrder(_ lhs: ReviewFinding, _ rhs: ReviewFinding) -> Bool {
        if lhs.file != rhs.file { return lhs.file < rhs.file }
        return lhs.line < rhs.line
    }

    private func row(_ finding: ReviewFinding) -> some View {
        let isOpen = finding.state == .open
        return Button {
            onJump(DiffLineAnchor(file: finding.file, side: finding.side, line: finding.line))
        } label: {
            HStack(spacing: 6) {
                Text("\(finding.file):\(finding.line)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isOpen ? Color.primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("—")
                    .foregroundStyle(.tertiary)
                Text(finding.comment)
                    .font(.caption)
                    .foregroundStyle(isOpen ? Color.primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isOpen, ReviewFindingStaleness.isStale(finding, in: files) {
                    Label("Line changed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if !isOpen {
                    Text("Sent · round \(finding.round ?? 0)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Scroll to line")
    }
}
