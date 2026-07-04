%% CONVENTIONS %%
- Strict concurrency is on. `@unchecked Sendable` and `@preconcurrency` need a comment + `notes.md` entry.
- Name actors for what they isolate (`ImageCache`, not `ImageActor`).
- `Task { }` only at boundaries with non-async worlds (UI events, `@main`, signal handlers).
- For safe unwrapping: `guard let … else { throw … }`. In tests: `try #require(...)`.
%% /CONVENTIONS %%

%% BUILD_AND_TEST %%
- Tests use **Swift Testing**: `import Testing`, `@Test`, `#expect`, `try #require(...)`.
- Test types: prefer `struct`. Use `class` only when you need `deinit` cleanup.
- While iterating, run only the affected suite (`swift test --filter` / `xcodebuild -only-testing:`) — the pre-commit gate runs the full suite behind every commit anyway.
- Pre-commit gate tooling: clean **SwiftLint** and **swift-format** lint. `// swiftlint:disable` requires a one-line justification.
%% /BUILD_AND_TEST %%

%% PITFALLS %%
- With default MainActor isolation, `nonisolated` on a type does **not** carry to its extensions — each `extension` needs its own `nonisolated`, or the compiler infers MainActor and calls from nonisolated contexts fail.
%% /PITFALLS %%
