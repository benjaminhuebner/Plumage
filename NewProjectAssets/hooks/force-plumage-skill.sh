#!/usr/bin/env bash
# force-plumage-skill.sh — UserPromptSubmit hook
#
# Two jobs when the user invokes a /plumage-<name> slash command:
#
# 1. Marker lifecycle for the plan-guard hooks. /plumage-plan writes a
#    session-scoped marker (<tmpdir>/plumage-plan-active/<session_id>); any other
#    /plumage-* (implement/review) removes it. block-during-plumage-plan.sh
#    reads this marker to know a plan turn is live and turns the skill's
#    "spec.md only" rule into a real PreToolUse riegel.
#    Marker: <tmpdir>/plumage-plan-active/<sanitized session_id>. Interview
#    replies (no slash command) leave the marker untouched — the script returns
#    before the marker logic when the prompt isn't a recognised /plumage-* command.
#
# 2. Inject a system reminder so the agent follows the project skill instead of
#    Claude Code's built-in Plan-Mode flow (Phase 1 Explore … Phase 5
#    ExitPlanMode, writes to ~/.claude/plans/). Plan Mode here is only an
#    edit-permission gate, not a workflow source.
#
# NOTE: /plumage-* skills are `disable-model-invocation`, so the agent must NOT
# call the Skill tool — the instructions are already in context (injected with
# the slash command). An earlier version of this hook ordered "FIRST tool call
# MUST be Skill(...)", which hard-fails for exactly that reason; corrected below.
#
# Fires only when a matching .claude/skills/plumage-<name>/ directory exists, so
# typos and unrelated slash commands are ignored. Fail open: missing jq or
# malformed input → exit 0, no injection, no marker change.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[ -z "$input" ] && exit 0

prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
[ -z "$prompt" ] && exit 0

# Capture the suffix after /plumage- at the start of the prompt (allowing
# leading whitespace). Skill names are alnum + dash + underscore.
skill_suffix=$(printf '%s' "$prompt" | sed -nE 's|^[[:space:]]*/plumage-([a-zA-Z0-9_-]+).*|\1|p' | head -n1)
[ -z "$skill_suffix" ] && exit 0

skill_name="plumage-${skill_suffix}"
skill_dir="${CLAUDE_PROJECT_DIR:-.}/.claude/skills/${skill_name}"

# Only fire when a matching skill actually exists. Otherwise the user is typing
# a slash command that isn't a project skill (or has a typo).
[ -d "$skill_dir" ] || exit 0

# --- Marker lifecycle (session-scoped; see header) ---
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
if [ -n "$session_id" ]; then
    safe=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_-')
    [ -z "$safe" ] && safe=default
    marker_dir="${TMPDIR:-/tmp}/plumage-plan-active"
    marker="${marker_dir}/${safe}"
    if [ "$skill_name" = "plumage-plan" ]; then
        mkdir -p "$marker_dir" 2>/dev/null && printf '%s\n' "$prompt" >"$marker" 2>/dev/null || true
    else
        rm -f "$marker" 2>/dev/null || true
    fi
fi

# --- Reminder injection ---
if [ "$skill_name" = "plumage-plan" ]; then
    cat <<EOF
<system-reminder>
ENFORCE-PLUMAGE-SKILL: The user invoked /${skill_name}. Its instructions are ALREADY in your context (injected with the slash command). Do NOT call the Skill tool — /plumage-* skills are disable-model-invocation and that call hard-fails. Follow the in-context instructions directly.

This is the project skill's OWN workflow, not Claude Code's built-in Plan-Mode flow (Phase 1 Explore … Phase 5 ExitPlanMode, writes to ~/.claude/plans/). Plan Mode here is only an edit-permission gate.

/plumage-plan writes ONLY into .claude/issues/<id>-<slug>/spec.md and finishes by setting \`status: approved\` in that spec. NEVER call ExitPlanMode, and never write code, branches, or commits (that is /plumage-implement). A PreToolUse hook now enforces both — a wrong write or ExitPlanMode will be denied.
</system-reminder>
EOF
else
    cat <<EOF
<system-reminder>
ENFORCE-PLUMAGE-SKILL: The user invoked /${skill_name}. Its instructions are ALREADY in your context (injected with the slash command). Do NOT call the Skill tool — /plumage-* skills are disable-model-invocation and that call hard-fails. Follow the in-context instructions directly, not Claude Code's built-in Plan-Mode flow.
</system-reminder>
EOF
fi
exit 0
