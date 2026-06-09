%% CONVENTIONS %%
- UI is **SwiftUI** with **AppKit** for: custom NSWindow chrome, complex toolbars, NSCursor work, drag-and-drop edge cases.
- Bridge with `NSViewRepresentable` / `NSHostingView`. When the project mixes both, follow its existing pattern — don't migrate AppKit to SwiftUI unrequested.
- Each window has its own scene-scoped state. Use `@FocusedValue`, `SceneStorage`, scene-scoped `@Observable` models, or per-document state.
- Document types: declare in Info.plist via `CFBundleDocumentTypes`.
%% /CONVENTIONS %%

%% BUILD_AND_TEST %%
- **IMPORTANT**: Use **XcodeBuildMCP** for builds and tests.
- <<<XCODE_MCP_LINE>>>
- Integration tests of scriptable apps (Finder, Safari, Mail, Music): use **applescript-mcp**, not hand-crafted `osascript` strings.
%% /BUILD_AND_TEST %%

%% PITFALLS %%
- Sandboxed apps cannot access arbitrary file paths. Use document API or security-scoped bookmarks. Plan in spec, not at the end.
- Keyboard shortcuts: `.keyboardShortcut(...)` on commands, not on views. `Commands` builder in the App scene.
%% /PITFALLS %%
