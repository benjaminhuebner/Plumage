#!/usr/bin/env bash
# guard-xcodebuild.sh — PreToolUse hook for Bash
#
# Enforces one discipline: xcodebuild runs in the foreground, one at a time.
# Two traps it blocks:
#
#   1. PARALLEL xcodebuild against this project — second call deadlocks on
#      DerivedData/SWBBuildService and looks like a hang.
#   2. BACKGROUND xcodebuild — if the call is rejected after `run_in_background`,
#      the subprocess orphans and blocks the next call.
#
# Exit 2 + stderr message blocks the tool call and surfaces the reason to
# the agent. Same exit-semantics as the other PreToolUse hooks in this dir.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "guard-xcodebuild: jq required" >&2
  exit 2
fi

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
bg=$(echo "$input" | jq -r '.tool_input.run_in_background // false')
[ -z "$cmd" ] && exit 0

# Only act when the command actually invokes xcodebuild. `xcodebuild` mentioned
# inside a string literal (e.g. echo or grep pattern) is fine.
if ! echo "$cmd" | grep -qE '(^|[[:space:];|&])xcodebuild([[:space:]]|$)'; then
  exit 0
fi

block() {
  printf 'guard-xcodebuild blocked: %s\n\n%s\n' "$1" "$2" >&2
  exit 2
}

# ---- Rule 1: no parallel xcodebuild against <<<PROJECT_NAME>>> --------------------------
#
# Use pgrep with the same project name. `xcodebuild -list` (cheap, ~1 s) is
# allowed even if another build is running because it's read-only on
# DerivedData, but we still warn — easier to just block uniformly.
if pgrep -f 'xcodebuild.*(-project[[:space:]]+<<<PROJECT_NAME>>>\.xcodeproj|-scheme[[:space:]]+<<<PROJECT_NAME>>>)' >/dev/null 2>&1; then
  running=$(ps -eo pid,etime,command | grep -E 'xcodebuild.*<<<PROJECT_NAME>>>' | grep -v grep | head -3)
  block "another xcodebuild against <<<PROJECT_NAME>>> is already running" \
"Currently running:
$running

Wait for it to finish, or if it's stuck, kill it first:
  pkill -9 -f 'xcodebuild.*<<<PROJECT_NAME>>>' ; pkill -9 -f 'SWBBuildService'

Two parallel xcodebuilds against the same project deadlock on
DerivedData/SWBBuildService."
fi

# ---- Rule 2: no background xcodebuild ---------------------------------------
#
# `run_in_background: true` is fine for long jobs in general, but xcodebuild
# specifically: if the call is later rejected/stopped, the subprocess often
# survives and orphans, blocking the next xcodebuild for 5–15 min.
if [ "$bg" = "true" ]; then
  block "run_in_background with xcodebuild is forbidden" \
"Background xcodebuild orphans on reject/stop and blocks subsequent
runs over the DerivedData lock. Run it in the foreground."
fi

exit 0
