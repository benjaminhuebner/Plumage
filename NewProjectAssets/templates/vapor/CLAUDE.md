%% LAYOUT %%
- `Sources/App/configure.swift` — app setup, middleware, database, route registration
- `Sources/App/routes.swift` — top-level routes, delegate to controllers
- `Sources/App/Controllers/` — one file per resource, methods grouped by HTTP verb
- `Sources/App/Models/` — Fluent models, one per file
- `Sources/App/DTO/` — request/response Codable types, separate from models
- `Sources/App/Migrations/` — explicit migrations only
%% /LAYOUT %%

%% CONVENTIONS %%
- DTOs separate from models. Fluent models stay internal to the data layer.
- Validate inputs in the controller before the database call.
- Business logic lives in controllers and services. Middleware is for cross-cutting concerns (auth, logging, CORS).
- Handler errors: `throw Abort(.status, reason: "…")`. The `reason` is returned to the client — write it for the API consumer, not for debugging.
- Database access goes through `req.db`. Never use a global `app.db` reference inside a request — it breaks per-request connection-pool scoping and transactions.
%% /CONVENTIONS %%

%% BUILD_AND_TEST %%
- Build/run: `swift run App` for dev, `swift build -c release` for prod.
- Endpoint smoke tests: **safari-mcp**. Start server, navigate, inspect HTML/JSON, read console. Default for "does this endpoint actually work" before writing the integration test.
- New tests: **VaporTesting** (Swift Testing). Existing: **XCTVapor**.
- Each test gets a fresh `Application` instance.
- In-memory SQLite for unit tests; real Postgres only for Postgres-specific behavior.
%% /BUILD_AND_TEST %%

%% PITFALLS %%
- Auto-migration is convenient and dangerous. Hides production data loss. Write explicit migrations, in every environment.
- Convert `EventLoopFuture` at boundaries; don't introduce new `EventLoopFuture` code in handlers.
- Blocking calls in a handler (sync file I/O, `sleep`, heavy CPU) stall the event loop for every request on it — use async APIs and offload CPU-heavy work.
%% /PITFALLS %%
