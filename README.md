<div align="center">

<img src="Docs/icon.png" width="116" alt="Plumage app icon">

# Plumage

**A native macOS workspace for the [Claude Code](https://claude.com/claude-code) workflow.**

*Issues, specs, an embedded agent, and local PR review — the spec-driven loop you'd otherwise run blind in a terminal, given a real UI you can see, steer, and review.*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE) [![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS%2026%2B-blue?style=flat-square)](#requirements) [![Swift 6](https://img.shields.io/badge/Swift-6-orange?style=flat-square)](#requirements) [![Status: experimental](https://img.shields.io/badge/status-experimental-orange?style=flat-square)](#about)

<a href="Docs/screenshots/hero.png"><img src="Docs/screenshots/hero.png" width="100%" alt="Plumage: Kanban board on the left, an embedded Claude Code session running on the right"></a>

</div>

> [!IMPORTANT]
> **Plumage is experimental, and a learning project first.** I built it mainly to
> *learn* Claude Code — to get hands-on with its agentic, spec-driven workflow by
> living inside it in a real, non-trivial macOS app instead of just reading about it.
> It turned out useful, but it's a personal learning project first and a tool second.
> You're welcome to use it, fork it, or take ideas from it, but it ships with **no
> support, no roadmap promises, and no stability guarantees.** Expect rough edges.

---

## Contents

- [About](#about)
- [Who it's for](#who-its-for)
- [Features](#features)
- [What makes it different](#what-makes-it-different)
- [The daily loop](#the-daily-loop)
- [Requirements](#requirements)
- [Building](#building)
- [Architecture](#architecture)
- [Built with](#built-with)
- [License](#license)

---

## About

Plumage embeds the [Claude Code](https://claude.com/claude-code) CLI — the `claude`
binary runs as a subprocess, and every interaction goes through it — but it's more
than a terminal wrapper. It turns the whole spec-driven loop into a native macOS
workspace: a Kanban board over your issues, an in-app spec editor, the agent docked
right next to the work (as a chat *and* a full terminal), and a local pull-request
review.

Out of the box, that workflow lives entirely in the terminal: issues are markdown
files you write by hand, a "run" is whatever progress you're holding in your head,
and a PR is a diff you scroll past in `git`. It works — but most of the structure
stays invisible. Plumage makes it tangible: specs with a frontmatter lifecycle, a
Kanban board where there used to be a folder, an agent one click away, and reviewable
`PR.md` artifacts instead of trust-the-agent commits.

It's explicitly **not** a replacement for the CLI — that's still where the work
happens. The point was never a better terminal; it was understanding the workflow
well enough to build something around it.

## Who it's for

Plumage is built for **Swift and Apple-platform developers**, on a **Claude Pro/Max
subscription**. The sharp edges all point that way: the bundled project templates
(SwiftUI apps, server-side Swift, Swift CLIs), the code snippets, the `swift-format`
/ SwiftLint pre-commit gates, the auto-installed Xcode tooling, and the in-app
build/run integration all assume a Swift project.

That's where Plumage is *sharpest* — not where it's *limited*. The Template Manager
lets you add templates for any project type you like, so nothing stops you from
taking it well beyond Swift.

## Features

<table>
  <tr>
    <td width="50%" valign="top">
      <a href="Docs/screenshots/welcome.png"><img src="Docs/screenshots/welcome.png" width="100%" alt="Welcome window"></a>
      <p><strong>Welcome window</strong><br>Reopen a recent project, scaffold a fresh one, or turn an existing folder into a Plumage project.</p>
    </td>
    <td width="50%" valign="top">
      <a href="Docs/screenshots/kanban.png"><img src="Docs/screenshots/kanban.png" width="100%" alt="Kanban board over .claude/issues/"></a>
      <p><strong>Kanban board over <code>.claude/issues/</code></strong><br>Your issues grouped by status. Drag between columns and the move writes straight back to each spec's frontmatter — the file system stays the source of truth.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <a href="Docs/screenshots/chat-dock.png"><img src="Docs/screenshots/chat-dock.png" width="100%" alt="Embedded Claude chat dock"></a>
      <p><strong>Embedded Claude — chat dock</strong><br>A floating dock runs a real <code>claude</code> session scoped to the open project, so you can ask questions and drive work without leaving the window.</p>
    </td>
    <td width="50%" valign="top">
      <a href="Docs/screenshots/issue-spec.png"><img src="Docs/screenshots/issue-spec.png" width="100%" alt="Issue spec editor"></a>
      <p><strong>Structured spec editor</strong><br>Every issue is a markdown spec with a typed frontmatter lifecycle (<code>draft → approved → in-progress → waiting-for-review → done</code>), edited in-app with syntax highlighting and live external-change detection.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <a href="Docs/screenshots/pull-request.png"><img src="Docs/screenshots/pull-request.png" width="100%" alt="Local pull-request review"></a>
      <p><strong>Local pull-request review</strong><br>Read the generated <code>PR.md</code> — summary, diff stats, commits, test notes — then merge or reject against local <code>git</code>. No GitHub token, no API, nothing leaves your machine.</p>
    </td>
    <td width="50%" valign="top">
      <a href="Docs/screenshots/template-manager.png"><img src="Docs/screenshots/template-manager.png" width="100%" alt="Template manager"></a>
      <p><strong>Project &amp; template manager</strong><br>Manage the templates, shared components, docs, hooks, agents and skills scaffolded into new projects — the Swift-first catalog, plus anything else you add.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <a href="Docs/screenshots/project-settings.png"><img src="Docs/screenshots/project-settings.png" width="100%" alt="Per-project settings"></a>
      <p><strong>Per-project settings</strong><br>Customize the workflow slash-commands and the permission mode passed to <code>claude</code> for each action. Saved to <code>.plumage/config.json</code>.</p>
    </td>
    <td width="50%" valign="top">
      <p><strong>Embedded Claude — terminal</strong><br>The same agent in a full terminal, docked right inside the project window — run Claude Code interactively (or any command) without switching apps. That's the panel on the right of the screenshot up top.</p>
    </td>
  </tr>
</table>

## What makes it different

- **Subscription-compliant by design.** Every Claude interaction goes through the
  `claude` CLI as a subprocess — no API key, no SDK, no `messages.create`. Plumage
  runs on your existing Claude Pro/Max subscription.
- **The file system is the source of truth.** Issues, specs, `PR.md`, configs and run
  state are plain files under `.claude/` and `.plumage/`. No database, no cloud, no
  sync — what's on disk is what survives a crash.
- **Local-first review.** The PR view runs entirely against local `git`. Ad-hoc
  commit / push / pull is there if you want it, but nothing requires a GitHub token.
- **Opinionated per-project setup.** On create, Plumage pins the right MCP servers
  (e.g. XcodeBuildMCP), recommends compatible plugins (Axiom for Apple platforms),
  and templates platform-specific snippets into `CLAUDE.md` and the workflow skills.

## The daily loop

Plumage is built around one dominant flow, in order:

1. **Open a project** → the Kanban board shows current issues, grouped by status.
2. **Plan an issue** → `/plumage-plan <slug>` interviews you in plan-mode, writes the
   spec, and sets its status to `approved`.
3. **Implement** → `/plumage-implement <slug>` runs the spec's tasks, commits per
   task behind a pre-commit gate, writes a `PR.md`, and sets status to
   `waiting-for-review`.
4. **Review** → open the `PR.md` and the diff, decide merge or reject.
5. **Merge locally** → status moves to `done`; the branch becomes history.

## Requirements

- **macOS 26** or later.
- **Xcode 26** (Swift 6, strict concurrency) to build.
- The **`claude` CLI** installed and on your `PATH` (Plumage shells out to it — it
  does not bundle or replace it), signed in to a Claude Pro/Max subscription.

## Building

```sh
git clone <your-fork-url> Plumage
cd Plumage
open Plumage.xcodeproj
```

Then build and run the `Plumage` scheme (<kbd>⌘R</kbd>). There is **no Swift Package
and no external build step** — Plumage is a single Xcode target with folder-based
modules; dependencies are resolved by Xcode via SwiftPM.

A few things to know before you build your own copy:

- **Set your own signing team.** The project currently hard-codes a
  `DEVELOPMENT_TEAM` (`F6A5PBNZF2`). Change it to your own under *Signing &
  Capabilities*, or override it locally, before building a signed copy.
- **It is not sandboxed — on purpose.** Plumage spawns `claude`, `git` and
  `swift-format` as subprocesses, which the App Sandbox would block. Mac App Store
  distribution is intentionally out of scope; direct download + notarization only.

<details>
<summary><strong>Forking to ship your own build?</strong></summary>

<br>

The app and its document types use the `com.benjaminhuebner.plumage.*` reverse-DNS
prefix (the bundle identifier in the Xcode project, plus a few Swift `UTType`
declarations). If you publish your own build, change that prefix to your own so it
doesn't clash with the original on macOS.

</details>

## Architecture

Single Xcode target, organized by folder-based modules rather than separate framework
targets. The app is SwiftUI with the MV (`@Observable`) pattern, Liquid Glass on the
navigation layer, and AppKit bridges where macOS needs them (window chrome, the
embedded terminal). One hard boundary: everything that touches Claude Code internals
lives in `ClaudeCodeIntegration/`, enforced by a CI grep test.

## Built with

Plumage is a SwiftUI app with no runtime backend — it orchestrates local tools
(`claude`, `git`, `swift-format`) as subprocesses. Its third-party dependencies,
resolved via Swift Package Manager:

| Dependency | What it's for |
| --- | --- |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | In-app software updates |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | The embedded terminal |
| [CodeEditorView](https://github.com/mchakravarty/CodeEditorView) | The integrated code & spec editor (pulls in [Rearrange](https://github.com/ChimeHQ/Rearrange)) |
| [Yams](https://github.com/jpsim/Yams) | YAML parsing for issue-spec frontmatter |

Everything else is Apple frameworks (SwiftUI, AppKit bridges, Liquid Glass).

## License

[MIT](LICENSE) © 2026 Benjamin Hübner

---

<sub>Plumage is an independent, unofficial project. It is not affiliated with,
endorsed by, or sponsored by Anthropic. "Claude" and "Claude Code" are products of
Anthropic.</sub>
