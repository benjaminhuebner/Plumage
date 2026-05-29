#!/usr/bin/env bash
# format-swift.sh — PostToolUse hook
#
# Auto-formats the just-edited Swift file using Apple's swift-format.
# Uses the project-root .swift-format config when present.
#
# Strictly non-blocking: missing tooling, formatter errors, or a since-deleted
# file all fall through silently. The point is convenience, not enforcement —
# the pre-commit gate catches anything that truly matters.
#
# This project commits .swift-format (Apple's swift-format config, ships with
# Xcode 16+) as the single source of truth. swiftformat (Nick Lockwood's
# different tool) is not used here — users who prefer it should disable this
# hook in .claude/settings.json.
#
# Wired up via .claude/settings.json:
#
#   "PostToolUse": [
#     {
#       "matcher": "Write|Edit|MultiEdit",
#       "hooks": [
#         { "type": "command",
#           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format-swift.sh" }
#       ]
#     }
#   ]

set -uo pipefail

# jq missing? Skip silently — this hook is convenience, not a gate.
command -v jq >/dev/null 2>&1 || exit 0

# swift-format missing? Skip silently. Ships with Xcode 16+ via `xcrun`, so
# the only reason it wouldn't be available is a stripped-down CI environment.
command -v swift-format >/dev/null 2>&1 || exit 0

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Only act on existing Swift files
[[ -z "$file_path" ]] && exit 0
[[ "$file_path" != *.swift ]] && exit 0
[[ ! -f "$file_path" ]] && exit 0

config_path="${CLAUDE_PROJECT_DIR:-.}/.swift-format"

if [[ -f "$config_path" ]]; then
    swift-format format --in-place --configuration "$config_path" "$file_path" 2>/dev/null || true
else
    swift-format format --in-place "$file_path" 2>/dev/null || true
fi

exit 0
