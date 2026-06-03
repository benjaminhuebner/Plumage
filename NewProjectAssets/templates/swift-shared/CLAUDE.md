%% CONVENTIONS %%
- Strict concurrency is on. `@unchecked Sendable` and `@preconcurrency` need a comment + `notes.md` entry.
- Name actors for what they isolate (`ImageCache`, not `ImageActor`).
- `Task { }` only at boundaries with non-async worlds (UI events, `@main`, signal handlers).
- For safe unwrapping: `guard let … else { throw … }`. In tests: `try #require(...)`.

%% BUILD AND TEST %%
- Tests use **Swift Testing**: `import Testing`, `@Test`, `#expect`, `try #require(...)`.
- Test types: prefer `struct`. Use `class` only when you need `deinit` cleanup.
