%% LAYOUT %%
- `Sources/App/App.swift` — `@main`, `AsyncParsableCommand`, CLI args, app bootstrap
- `Sources/App/Application+build.swift` — `buildApplication(args:)`, router and middleware wiring, service registration
- `Sources/App/Controllers/` — route handlers grouped by resource
- `Sources/App/Models/` — domain types
- `Sources/App/DTO/` — request/response Codable types

%% CONVENTIONS %%
- Define a custom **`RequestContext`** per service for per-request state (auth state, request ID, decoded user, trace span). `BasicRequestContext` is fine for spikes and small services.
- Use the result-builder routing API where it composes naturally.
- Middlewares conform to `MiddlewareProtocol` and call `next(request, context)`.
- Long-running work (background workers, scheduled jobs, websocket pumps) goes through **swift-service-lifecycle** registration. Keeps graceful shutdown working.
- Foundation imports stay out of route handlers unless actually needed.

%% BUILD AND TEST %%
- Build/run: `swift run App` for dev, `swift build -c release` for prod.
- Endpoint smoke tests: **safari-mcp**. Default for "does this endpoint actually work" before writing the integration test.
- Tests: **HummingbirdTesting** with the in-memory transport. Fast because it skips the network stack — keep it that way.

%% PITFALLS %%
- Forgetting to call `next(request, context)` in middleware drops the request silently.
- Detached `Task { }` for long-running work bypasses service-lifecycle's graceful shutdown.

%% SKILL_KEYWORDS %%
Hummingbird routing, RequestContext, swift-service-lifecycle, middleware, safari-mcp endpoint testing

%% PROJECT_TYPE_DESCRIPTION %%
Hummingbird server-side Swift backend
