# Run-state schema

Single source of truth for `<bundle>/runs/<slug>.json` (and `setup-project.json`), where `<bundle>` is the project's visible `*.plumage` bundle. Plumage's main loop and the `/plumage-implement` skill both write into this file; this document defines who writes which field and why.

**Note on `kind` values:** The `kind` field uses short internal discriminators (`implement`, `plan-issue`, `setup-project`) — these are *not* the skill names. Skill names are user-facing (`/plumage-implement`, `/plumage-plan`); `kind` values are short data labels chosen for compactness.

## File location

- Issue runs: `<bundle>/runs/<slug>.json` (slug matches the issue folder name, e.g. `00042-add-user-auth`)
- Project setup runs: `<bundle>/runs/setup-project.json`

Both under `<bundle>/runs/`. Resolve `<bundle>` by globbing the project root (the `claude` subprocess's `cwd`):

```sh
bundle=$(find . -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)
```

`! -name '.*'` excludes any legacy hidden `.plumage` dotfolder so it never shadows the real bundle. `runs/` (and `sessions/`) are gitignored *inside* the committable bundle, so relocating run-state here keeps it out of git even when the owner commits `<bundle>/`.

## Schema

```json
{
  "kind": "implement",
  "runId": "01HXY7ZA8K9P3QRSTV4WMNCDFG",
  "issue": "00042-add-user-auth",

  "startedAt": "2026-05-09T10:30:00Z",
  "lastUserVisibleAction": "Approved spec edit",

  "plumagePid": 12345,
  "plumageHeartbeatAt": "2026-05-09T10:42:13Z",

  "agentPid": 47291,
  "agentLastOutputAt": "2026-05-09T10:42:08Z",

  "phase": "running task 3",
  "lastProgressAt": "2026-05-09T10:38:01Z",

  "branch": "issue/00042-add-user-auth",
  "headBeforeRun": "abc123def456",
  "lastCompletedTask": 2,
  "totalTasks": 7
}
```

## Field ownership

| Field | Who writes | When | Notes |
|---|---|---|---|
| `kind` | skill (write once) | At fresh start | Values: `implement`, `plan-issue`, `setup-project` |
| `runId` | skill (write once) | At fresh start | ULID — survives PID recycling across crashes |
| `issue` | skill (write once) | At fresh start | Slug, e.g. `00042-add-user-auth` |
| `startedAt` | skill (write once) | At fresh start | ISO 8601 UTC |
| `lastUserVisibleAction` | Plumage | On UI events | Free text; safe to ignore from inside the skill |
| `plumagePid` | Plumage | At session start | The GUI's PID |
| `plumageHeartbeatAt` | Plumage | Every 10s | The GUI heartbeat — **the skill must not write this** |
| `agentPid` | skill (`start-run.sh`) | At fresh start AND on every resume | The long-lived `claude` session PID, resolved inside `start-run.sh` (parent of the tool shell). Re-bound on resume so a run continued in a new session is not swept as crashed |
| `agentLastOutputAt` | Plumage's PTY reader | Debounced to 1s | The skill **does not** write this — Plumage's PTY-read-handler updates it from observing terminal output |
| `phase` | skill | On every transition | Values: `starting`, `running task N`, `pre-commit-gate`, `writing PR.md`, `failed at task N` |
| `lastProgressAt` | skill | On phase change, task tick | Drives the Liveness verdict |
| `branch` | skill (write once) | At fresh start | `issue/<slug>` |
| `headBeforeRun` | skill (write once) | At fresh start | `git rev-parse <defaultBranch>` |
| `lastCompletedTask` | skill | After each task passes | Integer; 0 means none done yet |
| `totalTasks` | skill (write once) | At fresh start | Count of unchecked tasks in the spec |

The scripts own all writes. `scripts/start-run.sh` writes the initial document (fresh) or re-binds `agentPid`/counters (resume, spec ticks authoritative). During the per-task loop, `scripts/complete-task.sh` maintains `lastCompletedTask`, `phase`, and `lastProgressAt` (one atomic read-modify-write per completed task, setting the *next* phase; `--final-gate` advances `"pre-commit-gate"` → `"writing PR.md"`). Exceptional phases — `"failed at task <n>"`, `"needs-input: <question>"` — are written via `scripts/run-phase.sh`. The agent never edits the file by hand.

## Atomic writes

All writes to the run-state file must be atomic. Write the new JSON to `<bundle>/runs/<slug>.json.tmp`, then `mv` it to `<bundle>/runs/<slug>.json`. Never write in place — a crash mid-write would leave a half-written JSON exactly when recovery needs to read it.

The skill should also re-read the file before mutating, in case Plumage updated `plumageHeartbeatAt` or `agentLastOutputAt` since the last read. Read-modify-write is acceptable here because the skill mutates a different field set than Plumage does.

## What "fresh start" writes

At the start of a fresh run, the skill writes:

```json
{
  "kind": "implement",
  "runId": "<new ULID>",
  "issue": "<slug>",
  "startedAt": "<now>",
  "agentPid": <session PID: ps -o ppid= -p $$>,
  "phase": "starting",
  "lastProgressAt": "<now>",
  "branch": "issue/<slug>",
  "headBeforeRun": "<git rev-parse main>",
  "lastCompletedTask": 0,
  "totalTasks": <count of unchecked tasks>
}
```

Plumage adds the `plumage*` and `lastUserVisibleAction` fields on its own schedule. The agent and Plumage write disjoint field sets, so they don't race for the same keys — but the *file* still gets concurrent writers, hence atomic-rename.

## History records

A finished run is never plain-deleted: it moves to `<bundle>/runs/history/<slug>/<stamp>.json` (stamp = colon-free UTC time like `20260703T001720Z`; the app reads the JSON fields, the name only sorts and dedupes). History records are the run-state plus two fields:

| Field | Who writes | Values |
|---|---|---|
| `finishedAt` | archiver (write once) | ISO 8601 UTC |
| `outcome` | archiver (write once) | `completed`, `failed at task <N>`, `crashed` |

Who archives:

- **Skill** (`scripts/finish-run.sh <slug>`, Finish step): `outcome: completed`.
- **Plumage** (crashed-run sweep): a run-state whose `agentPid` is dead past a grace period and whose slug has no queue entry is moved with `outcome: crashed` — or `failed at task <N>` when the phase already says so.

Live scanners (Plumage and the fresh-start liveness checks) read only the top level of `runs/`; `runs/history/` and `runs/queue/` are invisible to them. The file leaving the top level is the completion signal Plumage's run notifier keys on. History grows unbounded on disk by design (file system is truth); the app caps what it *shows*, not what exists.

## Phase values

The `phase` field is a free-form string with these standard values:

- `"starting"` — initial state, before Task 1 runs (also set on resume)
- `"running task <N>"` — actively implementing Task N
- `"pre-commit-gate"` — last task done, running the gate
- `"writing PR.md"` — gate passed, writing the PR
- `"failed at task <N>"` — Task N failed twice, stopped
- `"needs-input: <question>"` — run blocked on a user decision; the Stop hook lets the turn end only on a finished, failed, or needs-input run

Plumage parses these to drive the status display. New phase strings are allowed if needed — Plumage shows them verbatim. The standard names should not change without a Plumage release that handles the renames.
