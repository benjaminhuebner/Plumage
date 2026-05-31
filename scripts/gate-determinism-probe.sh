#!/usr/bin/env bash
# gate-determinism-probe.sh — run the default pre-commit gate N times on the
# current working tree and report the pass rate.
#
# A green default gate is necessary but not sufficient: a flaky test passes most
# runs and fails occasionally, which shows up as a "grundlos rot" retry in the
# /plumage-implement loop. This probe makes that flakiness measurable — run it
# after migrating a polling test, or whenever a gate run failed without an
# obvious code cause.
#
# Usage:
#   scripts/gate-determinism-probe.sh [--runs N]   # default N = 10
#
# Exit codes:
#   0  all N runs passed
#   1  at least one run failed (the run logs are kept for inspection)
#   2  environment problem (gate script not found, not in a git repo, or a run
#      SKIPPED its tests so determinism cannot be assessed)

set -uo pipefail

runs=10
while [ $# -gt 0 ]; do
    case "$1" in
        --runs) runs="${2:-}"; shift 2 ;;
        --runs=*) runs="${1#*=}"; shift ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "error: unknown arg: $1" >&2; exit 2 ;;
    esac
done

case "$runs" in
    ''|*[!0-9]*) echo "error: --runs must be a positive integer" >&2; exit 2 ;;
esac
[ "$runs" -ge 1 ] || { echo "error: --runs must be >= 1" >&2; exit 2; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo_root" ] || { echo "error: not inside a git repository" >&2; exit 2; }
cd "$repo_root"

gate=".claude/skills/plumage-implement/scripts/precommit-gate.sh"
[ -x "$gate" ] || { echo "error: gate script not found/executable at $gate" >&2; exit 2; }

logdir="$(mktemp -d)"
commit="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "Probing the default gate ${runs}x on ${commit} (logs: ${logdir})"

pass=0
fail=0
for i in $(seq 1 "$runs"); do
    "$gate" --close-instances > "$logdir/run-$i.log" 2>&1
    rc=$?
    # The probe measures TEST determinism. If the Tests step was skipped (e.g. a
    # running app instance wedged the launch), a green exit is vacuous — refuse
    # to call the gate deterministic on data that never ran.
    if grep -qE '^\[2/7\] Tests\.\.\. SKIP' "$logdir/run-$i.log"; then
        echo "error: the Tests step was SKIPPED on run $i — cannot assess" >&2
        echo "       determinism without tests actually running." >&2
        echo "       (app instance running? see $logdir/run-$i.log)" >&2
        exit 2
    fi
    if [ $rc -eq 0 ]; then
        pass=$((pass + 1))
        printf 'run %2d/%d: PASS\n' "$i" "$runs"
    else
        fail=$((fail + 1))
        printf 'run %2d/%d: FAIL\n' "$i" "$runs"
        grep -E '^\[|GATE FAILED' "$logdir/run-$i.log" | sed 's/^/    /'
    fi
done

echo
echo "stability: ${pass}/${runs} passed"
if [ "$fail" -eq 0 ]; then
    rm -rf "$logdir"
    echo "DETERMINISTIC"
    exit 0
else
    echo "FLAKY — see ${logdir}/run-*.log for the failing runs"
    exit 1
fi
