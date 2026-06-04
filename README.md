# Plumage

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2026-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)

A native macOS desktop app for [Claude Code](https://claude.com/claude-code)
workflows. Plumage wraps the `claude` CLI as an embedded subprocess and layers a
Kanban board, an integrated editor, an embedded agent session, and a local PR
view on top — turning a raw terminal workflow into something you can see.

> **Status: v0.1** — an early public release. Built and dogfooded by one
> developer for Swift work on a Claude Pro/Max subscription. Expect rough edges.

## Why this exists

Claude Code's workflow lives in the terminal: issues are markdown files you write
by hand, runs are progress you track in your head, PRs are diffs you scroll
through in `git`. Plumage makes that workflow visible — structured specs with a
frontmatter lifecycle, a Kanban board over what was previously just a folder, and
reviewable `PR.md` artifacts instead of trust-the-agent commits.

The point is **not** to replace the CLI — the CLI is still where work happens.
The point is to put scaffolding around it.

## The daily loop

Plumage is built around one dominant flow, in order:

1. **Open a project** → the Kanban board shows current issues, grouped by status.
2. **Plan an issue** → `/plumage-plan <slug>` interviews you in plan-mode, writes
   the spec, and sets its status to `approved`.
3. **Implement** → `/plumage-implement <slug>` runs the spec's tasks, commits per
   task behind a pre-commit gate, writes a `PR.md`, and sets status to
   `waiting-for-review`.
4. **Review** → open the `PR.md` and the diff, decide merge or reject.
5. **Merge locally** → status moves to `done`; the branch becomes history.

## Screenshots

> _Screenshots are added in the v0.1 release pass; placeholders below._

| Kanban board | Issue detail |
|---|---|
| ![Kanban board](Docs/screenshots/kanban.png) | ![Issue detail](Docs/screenshots/issue-detail.png) |

| Embedded Claude dock | Template manager |
|---|---|
| ![Claude dock](Docs/screenshots/claude-dock.png) | ![Template manager](Docs/screenshots/template-manager.png) |

## Highlights

- **Kanban over `.claude/issues/`** — drag-and-drop status changes write straight
  back to each spec's frontmatter; the file system stays the source of truth.
- **Embedded agent** — a floating "Claude dock" runs a real `claude` session
  (chat + terminal modes) scoped to the open project, plus per-workflow tabs.
- **Integrated editor** — edit specs, `PR.md`, and project docs in-app with
  TextKit-2 syntax highlighting and live external-change detection.
- **Local PR view** — review the diff and the generated `PR.md` side by side; no
  GitHub token, no API, everything runs against local `git`.
- **Xcode integration** — build/run the open project and stream the log without
  leaving the window.

## Requirements

- **macOS 26** or later.
- **Xcode 26** (Swift 6, strict concurrency) to build.
- The **`claude` CLI** installed and on your `PATH` (Plumage shells out to it; it
  does not bundle or replace it). All Claude interaction goes through the CLI as a
  subprocess — there is no API key and no SDK, which keeps it compliant with
  Claude Pro/Max subscription usage.

## Building

```sh
git clone <your-fork-url> Plumage
cd Plumage
open Plumage.xcodeproj
```

Then build and run the `Plumage` scheme (⌘R). There is **no Swift Package and no
external build step** — Plumage is a single Xcode target with folder-based
modules; dependencies are resolved by Xcode via SwiftPM.

A few things contributors need to know:

- **Set your own signing team.** The project currently hard-codes a
  `DEVELOPMENT_TEAM` (`F6A5PBNZF2`). Change it to your own in *Signing &
  Capabilities*, or override it locally, before building a signed copy.
- **It is not sandboxed — on purpose.** Plumage spawns `claude`, `git`, and
  `swift-format` as subprocesses, which the App Sandbox would block. Mac App Store
  distribution is intentionally out of scope; direct download + notarization only.
- **Forking to ship?** The app and its document types use the
  `com.benjaminhuebner.plumage.*` reverse-DNS prefix (in `Info.plist` and a few
  Swift `UTType` declarations). If you publish your own build, change that prefix
  to your own so it doesn't clash with the original on macOS.

## Architecture

Single Xcode target, organized by folder-based modules rather than separate
framework targets. The app is SwiftUI with the MV (`@Observable`) pattern, Liquid
Glass on the navigation layer, and AppKit bridges where macOS needs them (window
chrome, the embedded terminal). One hard boundary: everything that touches Claude
Code internals lives in `ClaudeCodeIntegration/`, enforced by a CI grep test.

## License

[MIT](LICENSE) © 2026 Benjamin Hübner
