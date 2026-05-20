import SwiftUI

enum ClaudeStatusVisual {
    static func iconName(for indicator: ClaudeStatusIndicator) -> String {
        switch indicator {
        case .none: return "checkmark.circle.fill"
        case .minor: return "exclamationmark.triangle.fill"
        case .major, .critical: return "xmark.octagon.fill"
        case .maintenance: return "wrench.adjustable.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    static func tint(for indicator: ClaudeStatusIndicator) -> Color {
        switch indicator {
        case .none: return .green
        case .minor: return .yellow
        case .major, .critical: return .red
        case .maintenance: return .blue
        case .unknown: return .secondary
        }
    }
}

struct StatusPageButton: View {
    let model: ClaudeStatusModel
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: ClaudeStatusVisual.iconName(for: model.indicator))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ClaudeStatusVisual.tint(for: model.indicator))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .accessibilityIdentifier("statuspage-icon")
        .accessibilityLabel(Text(accessibilityLabel))
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            StatusPageDetailPopover(model: model)
        }
    }

    private var helpText: String {
        switch model.state {
        case .loading: return "Loading Anthropic status…"
        case .loaded(let response): return response.description
        case .error(let detail): return "Status unavailable: \(detail)"
        }
    }

    private var accessibilityLabel: String {
        switch model.state {
        case .loading: return "Anthropic status loading"
        case .loaded(let response): return "Anthropic status: \(response.description)"
        case .error: return "Anthropic status unavailable"
        }
    }
}

struct StatusPageDetailPopover: View {
    let model: ClaudeStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch model.state {
            case .loading:
                ProgressView("Loading…")
            case .error(let detail):
                Text("Could not refresh status.")
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            case .loaded(let response):
                loaded(response: response)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .accessibilityIdentifier("statuspage-popover")
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: ClaudeStatusVisual.iconName(for: model.indicator))
                .foregroundStyle(ClaudeStatusVisual.tint(for: model.indicator))
            Text("Anthropic status")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func loaded(response: ClaudeStatusPageResponse) -> some View {
        Text(response.description)
        if let component = response.component {
            HStack {
                Text("Claude Code")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(component.status.replacingOccurrences(of: "_", with: " "))
                    .font(.caption.monospacedDigit())
            }
            .font(.caption)
        }
        if !response.incidents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Active incidents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(response.incidents.enumerated()), id: \.offset) { _, incident in
                    HStack(alignment: .top, spacing: 4) {
                        Circle()
                            .fill(incidentTint(for: incident.impact))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(incident.name)
                                .font(.caption)
                            Text(incident.status.replacingOccurrences(of: "_", with: " "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func incidentTint(for impact: String) -> Color {
        switch impact {
        case "critical", "major": return .red
        case "minor": return .yellow
        case "maintenance": return .blue
        default: return .secondary
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
