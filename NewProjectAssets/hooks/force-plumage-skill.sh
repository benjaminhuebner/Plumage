#!/usr/bin/env bash
# force-plumage-skill.sh — UserPromptSubmit hook
#
# When the user invokes a /plumage-<name> slash command, injects a system
# reminder forcing the agent to load the matching skill via the Skill tool
# BEFORE any other action. Prevents the agent from falling into Claude
# Code's built-in Plan-Mode workflow (writes to ~/.claude/plans/) when the
# user actually wanted /plumage-plan to fill the issue's spec.md.
#
# Root cause this hook addresses: the Plan-Mode system reminder reads like
# a complete workflow (Phase 1 Explore … Phase 5 ExitPlanMode) and masks
# the fact that the actual workflow comes from the invoked skill. Plan
# Mode is only an edit-permission gate. Memory alone is not enough — a
# hook firing before the model's first token is the only thing that beats
# a louder built-in reminder.
#
# Fires only when a matching .claude/skills/plumage-<name>/ directory
# exists, so typos and unrelated slash commands are ignored.
#
# Fail open: missing jq or malformed input → exit 0, no injection.
#
# Wired via .claude/settings.json:
#
#   "UserPromptSubmit": [
#     {
#       "hooks": [
#         { "type": "command",
#           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/force-plumage-skill.sh" }
#       ]
#     }
#   ]

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

# Only fire when a matching skill actually exists. Otherwise the user is
# typing a slash command that isn't a project skill (or has a typo).
[ -d "$skill_dir" ] || exit 0

cat <<EOF
<system-reminder>
ENFORCE-PLUMAGE-SKILL: The user invoked /${skill_name}. Your FIRST tool call this turn MUST be Skill(skill: "${skill_name}") to load the project-local skill at .claude/skills/${skill_name}/.

Do NOT run Claude Code's built-in Plan-Mode workflow. The Plan-Mode system reminder (Phase 1 Explore … Phase 5 ExitPlanMode, writes to ~/.claude/plans/) is a generic fallback for when no skill applies. /${skill_name} is a project skill that defines its OWN workflow which replaces the generic one. Plan Mode here is only an edit-permission gate, not a workflow source.

If Plan Mode is also active, follow the skill's instructions while respecting Plan Mode's edit restrictions. /plumage-plan in particular writes into .claude/issues/<id>-<slug>/spec.md — never into ~/.claude/plans/.
</system-reminder>
EOF
exit 0
