import AppKit
import SwiftUI

struct GitHubImportSheet: View {
    @Bindable var model: GitHubImportModel
    let adoptedNumbers: Set<Int>
    let onDismiss: () -> Void
    var onConnectAccount: (() -> Void)?

    private enum Metrics {
        static let margin: CGFloat = 20
        static let rowVertical: CGFloat = 10
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 540, height: 560)
        .task { await model.load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Import GitHub Issues").font(.headline)
                if let subtitle = headerSubtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
            .disabled(model.isRefreshing)
            .help("Refresh")
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, Metrics.margin)
        .padding(.bottom, 12)
    }

    private var headerSubtitle: String? {
        guard let repo = model.repoLabel else { return nil }
        if case .loaded(let issues) = model.state {
            return "\(repo) · \(issues.count) open"
        }
        return repo
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            centered { ProgressView("Loading issues…") }
        case .loaded(let issues):
            List(issues) { issue in
                row(issue)
                    .listRowInsets(
                        EdgeInsets(
                            top: Metrics.rowVertical, leading: Metrics.margin,
                            bottom: Metrics.rowVertical, trailing: Metrics.margin)
                    )
                    .listRowSeparator(.visible)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        case .empty:
            centered {
                message("tray", "No open issues", "This repository has no open issues right now.")
            }
        case .unavailable(let reason, let connectAccount):
            centered {
                VStack(spacing: 16) {
                    message("point.3.connected.trianglepath.dotted", "Import unavailable", reason)
                    if connectAccount, let onConnectAccount {
                        Button("Connect a GitHub Account…", action: onConnectAccount)
                    }
                }
            }
        case .rateLimited(let message):
            centered {
                self.message(
                    "clock.badge.exclamationmark", "Rate limited",
                    message ?? "GitHub's rate limit was hit. Wait a moment and try Refresh.")
            }
        case .failed(let error):
            centered {
                VStack(spacing: 16) {
                    message("exclamationmark.triangle", "Couldn't load issues", error)
                    Button("Retry") { Task { await model.refresh() } }
                }
            }
        }
    }

    private func row(_ issue: GitHubIssue) -> some View {
        let adopted = adoptedNumbers.contains(issue.number) || model.justAdopted.contains(issue.number)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(issue.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("#\(issue.number)").font(.caption).foregroundStyle(.secondary)
                    ForEach(issue.labels, id: \.self) { label in
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            Spacer(minLength: 12)
            trailingControls(for: issue, adopted: adopted)
        }
        .padding(.vertical, 2)
        .opacity(adopted ? 0.55 : 1)
    }

    @ViewBuilder
    private func trailingControls(for issue: GitHubIssue, adopted: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                NSWorkspace.shared.open(issue.htmlURL)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Open on GitHub")

            if adopted {
                Label("Adopted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button("Adopt") { model.adopt(issue) }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let error = model.adoptError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Done", role: .cancel) { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.vertical, 12)
    }

    // MARK: Building blocks

    private func centered<Body: View>(@ViewBuilder _ body: () -> Body) -> some View {
        VStack { body() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Metrics.margin)
    }

    private func message(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
    }
}

#if DEBUG
#Preview("Loaded") {
    let model = GitHubImportModel(projectURL: URL(fileURLWithPath: "/tmp/demo"), boundAccountID: nil)
    model._setStateForTesting(
        .loaded([
            GitHubIssue(
                number: 42, title: "Crash when opening an empty project",
                body: "Steps to reproduce…",
                htmlURL: URL(string: "https://github.com/o/r/issues/42") ?? URL(fileURLWithPath: "/"),
                labels: ["bug", "v0.5"], updatedAt: .distantPast, authorLogin: "octocat"),
            GitHubIssue(
                number: 7, title: "Add a dark-mode toggle", body: nil,
                htmlURL: URL(string: "https://github.com/o/r/issues/7") ?? URL(fileURLWithPath: "/"),
                labels: ["enhancement"], updatedAt: .distantPast, authorLogin: "contrib"),
        ]), justAdopted: [7])
    return GitHubImportSheet(model: model, adoptedNumbers: [], onDismiss: {})
}
#endif
