#!/usr/bin/env bash
# block-during-plumage-plan.sh — PreToolUse hook (Write|Edit|MultiEdit|ExitPlanMode)
#
# Enforces the single rule that makes /plumage-plan a planning-only workflow:
# while a plan turn is active for this session, the ONLY allowed file write is
# the issue spec under .claude/issues/**, and ExitPlanMode is forbidden (it would
# drop the agent into Claude Code's generic approve→implement flow). Both are the
# same rule — "during /plumage-plan, nothing but the spec.md changes" — so they
# share one marker resolution here instead of two scripts kept in sync.
#
# Plan Mode itself enforces nothing in this setup (verified: under an active Plan
# Mode, writes to /tmp AND to Swift files both succeed), so this PreToolUse riegel
# is the only real guard.
#
# "Active" = a session-scoped marker written by force-plumage-skill.sh on
# /plumage-plan, cleared on /plumage-implement|review or once the spec reaches
# `status: approved`. Marker path + session-scoping mirror record-turn-base.py. A
# marker older than TTL_SECONDS is treated as orphaned (abandoned plan turn) —
# ignored and removed, so a stale marker can't wedge an unrelated later task in
# the same session.
#
# Fail OPEN: missing jq / malformed input / no marker → exit 0. A false negative
# (a stray write slips through) is far cheaper than wedging every Write in every
# session over a bookkeeping bug.

set -uo pipefail

TTL_SECONDS=7200

command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
[ -z "$input" ] && exit 0

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

safe=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_-')
[ -z "$safe" ] && safe=default
marker="${TMPDIR:-/tmp}/plumage-plan-active/${safe}"

# No active /plumage-plan for this session → nothing to enforce.
[ -f "$marker" ] || exit 0

# Orphaned marker (abandoned plan turn) → self-heal and allow.
now=$(date +%s)
mtime=$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0)
if [ $((now - mtime)) -gt "$TTL_SECONDS" ]; then
    rm -f "$marker"
    exit 0
fi

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')

# ExitPlanMode: /plumage-plan never exits via ExitPlanMode — it ends by writing
# `status: approved`, at which point stop-after-spec-approved.sh stops the turn.
if [ "$tool_name" = "ExitPlanMode" ]; then
    cat >&2 <<'EOF'
BLOCKED: /plumage-plan does not end with ExitPlanMode.

Finish planning by writing the spec under .claude/issues/<id>-<slug>/spec.md and
setting `status: approved` in its frontmatter. The stop-after-spec-approved hook
then ends the turn. Implementation runs separately via /plumage-implement.
EOF
    exit 2
fi

# Write/Edit/MultiEdit: allow only the skill's documented write zone (covers
# spec.md). Matches both the absolute path the tools pass and a repo-relative form.
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0
case "$file_path" in
    */.claude/issues/*|.claude/issues/*) exit 0 ;;
esac

cat >&2 <<EOF
BLOCKED: /plumage-plan may only write .claude/issues/<id>-<slug>/spec.md.
Attempted write to: ${file_path}

The Plan skill never writes code, branches, or commits — that is /plumage-implement.
Write the spec into the issue folder and set \`status: approved\` to finish planning.
EOF
exit 2
