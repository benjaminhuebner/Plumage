%% CONVENTIONS %%
- UI is **SwiftUI** unless the codebase says otherwise.
- Views run on the main actor. Off-main work goes in actors or `Task.detached`.
%% /CONVENTIONS %%

%% BUILD_AND_TEST %%
- **IMPORTANT**: Use **XcodeBuildMCP** for builds, tests, simulator boots, log streaming, device deployment.
- Tool names follow the `mcp__xcodebuildmcp__*` prefix. Full list via MCP discovery.
- <<<XCODE_MCP_LINE>>>
- Accessibility: non-text controls need labels, Dynamic Type up to AX5, one VoiceOver pass before moving spec to `waiting-for-review`.
%% /BUILD_AND_TEST %%

%% PROJECT_TYPE_DESCRIPTION %%
iOS app
%% /PROJECT_TYPE_DESCRIPTION %%
