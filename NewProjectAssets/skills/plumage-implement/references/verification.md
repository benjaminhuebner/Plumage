# Verification

How an implement run proves its work, tiered by cost. The tiers replace *interaction mechanics*, never judgment or coverage: a claim that needs pixels still gets pixels, and "UI wiring is verified by really running the app" stays binding. Climb the ladder only when the lower tier cannot observe the claim.

## The ladder

| Tier | Proves | Cost |
|---|---|---|
| 1. Tests (the gate) | Logic, data, state transitions — anything assertable in Swift Testing | Free (runs behind every commit anyway) |
| 2. AX tier: `osascript` + marker files | Functional UI wiring on the real running app: element exists, action fires, side effect happened | One Bash call per check |
| 3. `RenderPreview` (Xcode MCP) | Static looks of a single view, no app launch | One tool call |
| 4. computer-use | What needs pixels or real HID: Liquid Glass rendering, layout composition, focus behavior, drags | Screenshots inflate context permanently — budgeted |

Defaults per claim type:

- **"Tapping X causes Y"** → tier 2: `AXPress` the element, assert Y via marker file or real file-system output.
- **"View Z looks right in isolation"** → tier 3.
- **"The window composes correctly / glass renders / focus lands"** → tier 4, one pass.
- **New or changed visuals** → always one pixel pass (tier 4), regardless of what tiers 1–2 proved.

## App-instance bracket

Any manual launch, AX driving, or screenshot session against the app under test is bracketed by the gate's exclusive lock so parallel gates queue instead of killing the instance:

```bash
LOCK_OWNER_PID=$(ps -o ppid= -p $$) scripts/exclusive-lock.sh acquire --wait
# … launch, drive, verify …
# quit the app instance, THEN:
LOCK_OWNER_PID=$(ps -o ppid= -p $$) scripts/exclusive-lock.sh release
```

Quit the instance *before* releasing so the desktop is clean when the next gate fires; release *before* running your own gate (the gate's PID differs from the session PID and would queue behind your own lock). The `LOCK_OWNER_PID` prefix is required in agent sessions: each tool shell dies by the next call; evaluated in the tool shell, the expression yields the long-lived session PID.

Launching the build under test:

- Resolve the app via `xcodebuild -showBuildSettings … | grep BUILT_PRODUCTS_DIR` — never glob DerivedData (stale twins exist) and never trust bundle `mtime` (directory mtime survives rebuilds). Freshness is `** BUILD SUCCEEDED **` from the build that just ran.
- Launch with `open -a "$BUILT_PRODUCTS_DIR/<App>.app" <project>.plumage`.
- A wedged instance is usually an Xcode debug session: check ancestry with `ps -o pid,ppid,stat,command -p <pid>` — parent `debugserver`/Xcode means kill the `debugserver` PID (or Stop in Xcode), parent `1` means true orphan.

## AX tier: osascript recipes

Targeted queries only — `entire contents` walks the whole tree and can take minutes on a real window. Address the element, ask one question.

```bash
# Existence / labels of controls (one container at a time)
osascript -e 'tell application "System Events" to tell process "Plumage" to get name of buttons of toolbar 1 of window 1'

# Press a control by accessibility identifier (SwiftUI .accessibilityIdentifier surfaces as AXIdentifier)
osascript -e 'tell application "System Events" to tell process "Plumage" to perform action "AXPress" of (first button of window 1 whose value of attribute "AXIdentifier" is "implement-button")'

# Click a menu item (more reliable than synthetic modifier shortcuts)
osascript -e 'tell application "System Events" to tell process "Plumage" to click menu item "New Issue" of menu "File" of menu bar 1'

# Window size / position (synthetic edge-drags do not resize AppKit windows)
osascript -e 'tell application "System Events" to tell process "Plumage" to set size of window 1 to {1480, 780}'

# Read displayed text
osascript -e 'tell application "System Events" to tell process "Plumage" to get value of first static text of window 1'
```

Add an `accessibilityIdentifier` only when the element lacks a stable title *and* will be verified again; when the AX tier cannot address an element at all, fall through to computer-use for that one check.

Known limits (all field-verified, see notes.md for the full entries):

- **Glass groups are invisible in the AX hierarchy** — toolbar grouping/spacing is verifiable only by screenshot.
- **Synthetic ESC does not reach NSEvent local monitors during a synthetic drag** — the drag keeps running and a later mouse-up commits. ESC-cancel needs a real keyboard; in synthetic tests cancel a drag by releasing outside the valid zone (snap-back).
- **Option-modifier key equivalents are flaky synthetically** (`option+t` produces a dead key, not the equivalent). Shift-based shortcuts fire fine; otherwise click the menu item.
- **Plain-NSView `NSDraggingDestination` needs a real HID drag.** SwiftUI `DragGesture`/`.dropDestination` and AppKit `NSOutlineView` drag sessions are all drivable with stepped synthetic drags.
- **Close unrelated app windows first** — a Welcome-style window steals key focus and synthetic typing lands on its default button.
- **A screenshot/zoom forces a redraw** and can mask missing live-observation wiring; verify "updates live" claims with an AX value read *before* any screenshot.
- A Debug-built instance that ignores `quit`/SIGTERM is parked under a debugger or already a zombie — see the ancestry check above; `open -n` starts a fresh instance System Events can talk to.

## Marker-file pattern

`os.Logger` output is not reliably visible via `log show` from a Debug app — use marker files as ground truth for side effects that have no observable file-system output:

```swift
try? "reached \(Date())".write(toFile: "/tmp/plumage-marker-dropHandler", atomically: true, encoding: .utf8)
```

```bash
rm -f /tmp/plumage-marker-dropHandler   # arm
# … AXPress / interaction …
test -f /tmp/plumage-marker-dropHandler && echo WIRED || echo "NOT REACHED"
```

Markers are scaffolding: remove them before the task's commit. Prefer asserting the real output (a file written, a spec field flipped, a git ref moved) whenever one exists.

## computer-use economy

- `request_access` happens once, during Fresh start — never mid-loop.
- `computer_batch` first: one batched move/click/type sequence per interaction, not one call per event.
- Screenshot budget: one per claim that genuinely needs pixels, hard cap ~3 per task (a dedicated visual-design task may exceed it deliberately). Use `zoom` on a region instead of a second full screenshot.
- Evidence that only needs to *exist* (not be judged by the main agent) goes to files: `screencapture -l<windowID> /tmp/…png`, window ID from a `CGWindowListCopyWindowInfo` Swift one-liner (front-to-back order — first match is the front-most window of the app, not the largest). Downscale Retina captures with `sips --resampleWidth 1600` before reading.

## Acceptance subagent

For a checklist-style acceptance pass (several observable claims against one app state), delegate to a subagent so the screenshots inflate *its* context, not the run's. The main session builds, launches the fresh app, and **holds the exclusive lock around the whole Agent call** — a crashed subagent can then never leak the lock. Prompt template:

```
Verify the following claims against the running app "<App>" (window "<title>").
The app is already running — do not build, launch, quit, or relaunch it, and
do not touch any lock script.

Claims (verify each independently):
1. <numbered, observable claim — one assertable fact each>
2. …

Method: prefer osascript/System Events queries and AXPress; use computer-use
only where pixels or real interaction are required. Save every screenshot to
/tmp/accept-<slug>-<claim>.png (screencapture -l<windowID>); never rely on a
screenshot you did not save.

Report per claim: PASS | FAIL | UNCLEAR, one sentence of observed evidence,
and the screenshot path(s) if any. End with the total interaction count and
any claim you could not address, with the reason.
```

Verdict rules, non-negotiable:

- Any FAIL or UNCLEAR → the task's failure path. Never downgraded to "probably fine".
- A crashed subagent, or a verdict missing per-claim evidence, **is** UNCLEAR by definition.
- On FAIL the main agent `Read`s the referenced screenshot(s) before deciding the fix — evidence first, then diagnosis.
