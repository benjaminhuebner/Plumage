%% CONVENTIONS %%
- View models: `@Observable`, not `ObservableObject`. `@Bindable` for two-way bindings.
- `@Environment` for shared services. Don't prop-drill through 5+ view layers.
- `NavigationStack` with `.navigationDestination(for:)` for type-safe routing.

%% PITFALLS %%
- Liquid Glass: navigation layer only (toolbars, sidebars, floating controls). Never on cards, list rows, or content surfaces.
- Don't stack glass on glass — wrap close elements in `GlassEffectContainer`.
- `.glassEffect()` variants: `.regular`, `.clear`, `.identity`. There is no `.prominent` — for a prominent button use `.buttonStyle(.glassProminent)`.
- Toolbars and `NavigationSplitView` sidebars get glass automatically. Don't apply it manually there.

%% SKILL_KEYWORDS %%
SwiftUI architecture, @Observable view models, NavigationStack routing, Liquid Glass
