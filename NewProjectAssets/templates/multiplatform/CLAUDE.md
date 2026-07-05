## Project layout
- `Sources/Shared/` — domain logic, models, view models, anything platform-agnostic
- `Sources/iOS/` — iOS-specific UI and integrations
- `Sources/macOS/` — macOS-specific UI and integrations

## Conventions
- Keep `#if os(...)` blocks short. Long platform-specific code goes into platform-specific files.
- `#if canImport(UIKit)` inside a platform-specific file is fine. Sprinkled across shared code, it's a smell.
- Reach for `UIViewRepresentable` / `NSViewRepresentable` only at the edges. Isolate in platform-specific files.

## Build and test
- **IMPORTANT**: Use **XcodeBuildMCP** for every destination. Run all destinations before marking spec `waiting-for-review`.
<<<XCODE_MCP_LINE>>>
- macOS integration tests: **applescript-mcp**.

## Common pitfalls
- Most platform-divergent bugs surface on macOS first (multi-window, keyboard navigation, menubar, AppKit interop). Test there too — passing on iOS doesn't mean passing on macOS.
- Keyboard shortcuts for the macOS destination: `.keyboardShortcut(...)` on commands (`Commands` builder in the App scene), not on views.
