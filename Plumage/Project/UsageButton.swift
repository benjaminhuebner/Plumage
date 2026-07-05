import SwiftUI

struct UsageButton: View {
    let model: ClaudeUsageModel
    @State private var showPopover = false
    @AppStorage(UsageDisplaySettings.showFiveHourKey) private var showFiveHour: Bool =
        UsageDisplaySettings.showFiveHourDefault
    @AppStorage(UsageDisplaySettings.showSevenDayKey) private var showSevenDay: Bool =
        UsageDisplaySettings.showSevenDayDefault

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
            ProgressView()
                .controlSize(.mini)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
        case .loggedOut, .error:
            minimalIcon
        case .usage(let response):
            usageLabel(for: response)
        }
    }

    @ViewBuilder
    private func usageLabel(for response: ClaudeUsageResponse) -> some View {
        let segments = selectedSegments(for: response)
        if segments.isEmpty {
            minimalIcon
        } else {
            segmentPill(segments)
        }
    }

    private func segmentPill(_ segments: [UsageSegment]) -> some View {
        let tint = Self.percentColor(segments.map(\.pct).max() ?? 0)
        return HStack(spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text("·").foregroundStyle(.secondary)
                }
                Text("\(segment.label): \(Self.format(percent: segment.pct))")
                    .foregroundStyle(Self.percentColor(segment.pct))
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule(style: .continuous).fill(tint.opacity(0.15)))
        .overlay(Capsule(style: .continuous).stroke(tint.opacity(0.35), lineWidth: 0.5))
    }

    private var minimalIcon: some View {
        Image(systemName: "gauge.medium")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
    }

    static func percentColor(_ pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .green
    }

    private var helpText: String {
        switch model.state {
        case .loading: return "Loading Claude usage…"
        case .loggedOut: return "Claude CLI not logged in"
        case .error(let detail): return "Usage unavailable: \(detail)"
        case .usage(let response):
            let segments = selectedSegments(for: response)
            guard !segments.isEmpty else { return "Claude usage — click for details" }
            return segments.map { "\($0.label) \(Self.format(percent: $0.pct))" }
                .joined(separator: " · ")
        }
    }

    private var accessibilityLabel: String {
        switch model.state {
        case .loading: return "Claude usage loading"
        case .loggedOut: return "Claude usage unavailable, not logged in"
        case .error: return "Claude usage unavailable"
        case .usage(let response):
            let segments = selectedSegments(for: response)
            guard !segments.isEmpty else { return "Claude usage, click for details" }
            return "Claude usage: "
                + segments.map { "\($0.label) \(Self.format(percent: $0.pct))" }
                .joined(separator: ", ")
        }
    }

    private func selectedSegments(for response: ClaudeUsageResponse) -> [UsageSegment] {
        response.pillSegments(showFiveHour: showFiveHour, showSevenDay: showSevenDay)
    }

    static func format(percent value: Double) -> String {
        // Branch on the raw value so 9.95 doesn't jump straight to "10%" by
        // way of clamped+rounded — sub-10 values stay in the one-decimal form
        // ("9.4%", "10.0%") and 10+ collapse to integers ("42%", "100%").
        let clamped = max(0, min(value, 999))
        return value >= 10
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
                row(
                    label: "5-hour window", window: five,
                    accent: UsageButton.percentColor(five.utilizationPct))
            }
            if let week = model.sevenDay {
                row(
                    label: "7-day window", window: week,
                    accent: UsageButton.percentColor(week.utilizationPct))
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
