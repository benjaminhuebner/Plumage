%% LAYOUT %%
- `Sources/Shared/` — domain logic, models, view models, anything platform-agnostic
- `Sources/iOS/` — iOS-specific UI and integrations
- `Sources/macOS/` — macOS-specific UI and integrations
%% /LAYOUT %%

%% CONVENTIONS %%
- Keep `#if os(...)` blocks short. Long platform-specific code goes into platform-specific files.
- `#if canImport(UIKit)` inside a platform-specific file is fine. Sprinkled across shared code, it's a smell.
- Reach for `UIViewRepresentable` / `NSViewRepresentable` only at the edges. Isolate in platform-specific files.
%% /CONVENTIONS %%

%% BUILD_AND_TEST %%
- **IMPORTANT**: Use **XcodeBuildMCP** for every destination. Run all destinations before marking spec `waiting-for-review`.
- <<<XCODE_MCP_LINE>>>
- macOS integration tests: **applescript-mcp**.
%% /BUILD_AND_TEST %%

%% PITFALLS %%
- Most platform-divergent bugs surface on macOS first (multi-window, keyboard navigation, menubar, AppKit interop). Test there too — passing on iOS doesn't mean passing on macOS.
%% /PITFALLS %%

%% PROJECT_TYPE_DESCRIPTION %%
multiplatform Apple-platform (iOS + macOS)
%% /PROJECT_TYPE_DESCRIPTION %%
