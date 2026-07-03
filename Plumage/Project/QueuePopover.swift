import SwiftUI

nonisolated struct QueueEntryDisplay: Equatable, Sendable, Identifiable {
    let position: Int
    let slug: String
    let isCancelable: Bool

    var id: String { slug }
}

nonisolated enum QueueDisplayBuilder {
    static func entries(
        from queue: [QueuedImplementRun], cancelable: (String) -> Bool
    ) -> [QueueEntryDisplay] {
        queue.enumerated().map { index, run in
            QueueEntryDisplay(
                position: index + 1, slug: run.issue, isCancelable: cancelable(run.issue))
        }
    }
}

struct QueueStatusButton: View {
    let entries: [QueueEntryDisplay]
    let onCancel: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.number")
                Text("\(entries.count) queued")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            QueuePopoverContent(entries: entries, onCancel: onCancel)
        }
        .accessibilityLabel("\(entries.count) queued implement runs")
    }
}

private struct QueuePopoverContent: View {
    let entries: [QueueEntryDisplay]
    let onCancel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Waiting for the checkout")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Text("\(entry.position).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(entry.slug)
                        .font(.caption.monospaced())
                    Spacer(minLength: 12)
                    if entry.isCancelable {
                        Button {
                            onCancel(entry.slug)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel this waiting run (closes its terminal tab)")
                        .accessibilityLabel("Cancel queued run \(entry.slug)")
                    } else {
                        Text("external")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .help("Started outside Plumage — cancel it from its own terminal")
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 260, alignment: .leading)
    }
}

#Preview {
    QueueStatusButton(
        entries: [
            QueueEntryDisplay(position: 1, slug: "00123-diff-viewer-upgrade", isCancelable: true),
            QueueEntryDisplay(position: 2, slug: "00124-issue-relations", isCancelable: false),
        ],
        onCancel: { _ in }
    )
    .padding(40)
}
