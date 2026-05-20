import Foundation

// Domain module for read-only Anthropic account metadata (usage + status).
// Boundary per decisions.md 2026-05-20 (#00031-claude-usage-statusbar):
// SwiftUI-free, no Inferenz, no own credentials — read-only piggyback on the
// existing CLI keychain item and the public status.claude.com endpoint.
nonisolated enum ClaudeAccount {}
