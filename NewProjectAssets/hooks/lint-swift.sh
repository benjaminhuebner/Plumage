#!/usr/bin/env bash
# lint-swift.sh — PostToolUse hook
#
# Runs SwiftLint on the Swift file that was just edited and surfaces violations
# back to Claude as feedback. The edit itself is NOT blocked (it already
# happened); the hook just nudges the agent to fix the violations on the next
# turn rather than waiting for the pre-commit gate to catch dozens at once.
#
# Wired up via .claude/settings.json:
#
#   "PostToolUse": [
#     {
#       "matcher": "Write|Edit|MultiEdit",
#       "hooks": [
#         { "type": "command",
#           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/lint-swift.sh" }
#       ]
#     }
#   ]

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "Hook error: jq is not installed. Install it (macOS: 'brew install jq') so safety hooks work." >&2
  exit 2
fi

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Only act on existing Swift files
[[ -z "$file_path" ]] && exit 0
[[ "$file_path" != *.swift ]] && exit 0
[[ ! -f "$file_path" ]] && exit 0

# Tolerate missing tooling — don't fail the user's workflow if swiftlint isn't
# installed yet
command -v swiftlint >/dev/null 2>&1 || exit 0

# Lint just the touched file
raw=$(swiftlint lint --quiet "$file_path" 2>&1) || true

# Filter to actual violation lines (path:line:col: ...). Drops config-noise
# like rule-rename warnings that would otherwise flag every edit.
output=$(printf '%s\n' "$raw" | grep -E "^${file_path}:[0-9]+:[0-9]+:" || true)

if [[ -n "$output" ]]; then
  {
    echo "SwiftLint violations in $file_path:"
    echo ""
    echo "$output"
    echo ""
    echo "Fix in your next edit. Do not suppress with \`// swiftlint:disable\` without a one-line justification."
  } >&2
  exit 2
fi

exit 0
