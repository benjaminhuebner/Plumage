## Conventions
- View models: `@Observable`, not `ObservableObject`. `@Bindable` for two-way bindings.
- `@Environment` for shared services. Don't prop-drill through 5+ view layers.
- Type-safe routing: `NavigationStack` + `.navigationDestination(for:)` where a real push hierarchy exists; sidebar/list-detail apps are selection-driven `NavigationSplitView` (typed route enum, no stack).

## Build and test
- `xcodebuild`/tests always **serial** — never two builds on the same project (they deadlock over DerivedData/SWBBuildService). The pre-commit gate enforces this via its cross-worktree lock; direct `xcodebuild` calls outside the gate stay discipline.

## Common pitfalls
- Liquid Glass: navigation layer only (toolbars, sidebars, floating controls). Never on cards, list rows, or content surfaces.
- Don't stack glass on glass — wrap close elements in `GlassEffectContainer`.
- `.glassEffect()` variants: `.regular`, `.clear`, `.identity`. There is no `.prominent` — for a prominent button use `.buttonStyle(.glassProminent)`.
- Toolbars and `NavigationSplitView` sidebars get glass automatically. Don't apply it manually there.
- A clean build and green unit tests do **not** prove SwiftUI lifecycle wiring (`.task`, `.onChange`, environment injection) — verify by launching the app and checking a real side effect.
- A running instance of the app under test wedges `xcodebuild`'s test launch (macOS test hosts) — quit instances before testing; the pre-commit gate closes them itself.
