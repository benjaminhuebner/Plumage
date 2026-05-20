import SwiftUI

struct UsageButton: View {
    let model: ClaudeUsageModel
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            label
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .accessibilityIdentifier("usage-pill")
        .accessibilityLabel(Text(accessibilityLabel))
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            UsageDetailPopover(model: model)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("5h…")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
        case .loggedOut, .error:
            pill(text: "5h: —", tint: .secondary)
        case .usage:
            pill(text: pillText, tint: pillColor)
        }
    }

    private func pill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 0.5)
            )
    }

    private var pillText: String {
        guard let pct = model.fiveHour?.utilizationPct else { return "5h: —" }
        return "5h: \(Self.format(percent: pct))"
    }

    private var pillColor: Color {
        guard let pct = model.fiveHour?.utilizationPct else { return .secondary }
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .green
    }

    private var helpText: String {
        switch model.state {
        case .loading: return "Loading Claude usage…"
        case .loggedOut: return "Claude CLI not logged in"
        case .error(let detail): return "Usage unavailable: \(detail)"
        case .usage:
            let five = model.fiveHour.map { "5h \(Self.format(percent: $0.utilizationPct))" } ?? "5h —"
            let week = model.sevenDay.map { "7d \(Self.format(percent: $0.utilizationPct))" } ?? "7d —"
            return "\(five) · \(week)"
        }
    }

    private var accessibilityLabel: String {
        switch model.state {
        case .loading: return "Claude usage loading"
        case .loggedOut: return "Claude usage unavailable, not logged in"
        case .error: return "Claude usage unavailable"
        case .usage:
            guard let pct = model.fiveHour?.utilizationPct else { return "Claude usage unavailable" }
            return "Claude 5-hour window \(Self.format(percent: pct))"
        }
    }

    static func format(percent value: Double) -> String {
        let clamped = max(0, min(value, 999))
        return clamped >= 10
            ? "\(Int(clamped.rounded()))%"
            : String(format: "%.1f%%", clamped)
    }
}

struct UsageDetailPopover: View {
    let model: ClaudeUsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude usage")
                .font(.headline)
            switch model.state {
            case .loading:
                ProgressView("Loading…")
            case .loggedOut:
                Text("Claude CLI is not logged in.")
                    .foregroundStyle(.secondary)
            case .error(let detail):
                Text("Could not refresh usage.")
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            case .usage:
                usageRows
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .accessibilityIdentifier("usage-popover")
    }

    @ViewBuilder
    private var usageRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let five = model.fiveHour {
                row(label: "5-hour window", window: five, accent: percentColor(five.utilizationPct))
            }
            if let week = model.sevenDay {
                row(label: "7-day window", window: week, accent: percentColor(week.utilizationPct))
            }
            if let opus = model.sevenDayOpus, opus.utilizationPct > 0 {
                row(label: "7-day Opus", window: opus, accent: percentColor(opus.utilizationPct))
            }
            if let sonnet = model.sevenDaySonnet, sonnet.utilizationPct > 0 {
                row(
                    label: "7-day Sonnet", window: sonnet,
                    accent: percentColor(sonnet.utilizationPct))
            }
        }
    }

    private func row(label: String, window: ClaudeUsageResponse.WindowUsage, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(UsageButton.format(percent: window.utilizationPct))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(accent)
            }
            if let resets = window.resetsAt {
                Text("Resets \(resets, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percentColor(_ pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .green
    }

    @ViewBuilder
    private var footer: some View {
        if let refreshed = model.lastRefreshedAt {
            Text("Last refreshed \(refreshed, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Refreshing in the background…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
