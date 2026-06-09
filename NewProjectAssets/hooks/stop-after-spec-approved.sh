#!/usr/bin/env bash
# stop-after-spec-approved.sh — PostToolUse hook
#
# Fires after Edit/Write/MultiEdit on .claude/issues/*/spec.md. If the edit
# wrote `status: approved` into the spec's frontmatter, blocks the agent's
# turn from continuing into anything else — the Plan workflow ends here, the
# rest belongs to a separate /plumage-implement session.
#
# This is the technical enforcement behind the plumage-plan SKILL.md claim
# that "the Plan Mode subprocess exits on its own once the spec reaches
# approved" — without this hook, the agent is free to keep tool-calling
# after ExitPlanMode is accepted, and frequently does.
#
# Fail open: if jq is missing or the hook hits an unexpected error, we let
# the action through. The failure mode here is "agent might continue into
# implementation" — annoying, not destructive — so blocking on hook breakage
# would be worse than letting it slip.
#
# Trigger condition: `new_string` (Edit/MultiEdit) or `content` (Write)
# contains a line `status: approved`. Body-level mentions are theoretically
# possible inside code fences but vanishingly unlikely in a spec.
#
# Wired up via .claude/settings.json:
#
#   "PostToolUse": [
#     {
#       "matcher": "Edit|Write|MultiEdit",
#       "hooks": [
#         { "type": "command",
#           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-after-spec-approved.sh" }
#       ]
#     }
#   ]

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[ -z "$input" ] && exit 0

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
case "$tool_name" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0

# Only care about issue specs. Match any padding under .claude/issues/.
case "$file_path" in
    */.claude/issues/*/spec.md) ;;
    *) exit 0 ;;
esac

# Pull the payload the agent just wrote. For MultiEdit, concatenate every
# new_string so a single approving edit anywhere in the batch counts.
case "$tool_name" in
    Edit)
        payload=$(printf '%s' "$input" | jq -r '.tool_input.new_string // ""')
        ;;
    Write)
        payload=$(printf '%s' "$input" | jq -r '.tool_input.content // ""')
        ;;
    MultiEdit)
        payload=$(printf '%s' "$input" | jq -r '[.tool_input.edits[]?.new_string // ""] | join("\n")')
        ;;
esac

# Frontmatter line — anchored, exactly one space after the colon, no quotes.
# Matches how IssueStatus serializes ("status: approved"), nothing else.
if ! printf '%s' "$payload" | grep -qE '^status:[[:space:]]+approved[[:space:]]*$'; then
    exit 0
fi

# Planning is done — clear the session-scoped plan-active marker so the
# block-write / block-exit-plan guards stop firing (see force-plumage-skill.sh).
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
if [ -n "$session_id" ]; then
    safe=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_-')
    [ -z "$safe" ] && safe=default
    rm -f "${TMPDIR:-/tmp}/plumage-plan-active/${safe}" 2>/dev/null || true
fi

cat >&2 <<'EOF'
Plan workflow complete: spec.md now has `status: approved`.

STOP HERE. Do not call any further tools in this turn. Output only the
one-line confirmation ("Spec approved. Run /plumage-implement <id>-<slug>
when ready.") and end your turn.

Implementation runs in a separate /plumage-implement session — never as a
continuation of /plumage-plan. The Plan skill explicitly does NOT create
branches, commits, or code; that boundary is what this hook enforces.
EOF
exit 2
