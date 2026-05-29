#!/usr/bin/env bash
# block-secrets-in-content.sh — PreToolUse hook
#
# Scans content being written/edited for hardcoded secrets. Blocks the write.
# Conservative: matches well-known prefixes and high-entropy patterns that
# are unlikely to false-positive on normal code.
#
# Wired up via .claude/settings.json:
#
#   "PreToolUse": [
#     {
#       "matcher": "Write|Edit|MultiEdit",
#       "hooks": [
#         { "type": "command",
#           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-secrets-in-content.sh" }
#       ]
#     }
#   ]

set -uo pipefail

# Require jq. Without it, JSON parsing fails silently and hooks become useless.
if ! command -v jq >/dev/null 2>&1; then
  echo "Hook error: jq is not installed. Install it (macOS: 'brew install jq') so safety hooks work." >&2
  exit 2
fi

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')

content=$(echo "$input" | jq -r '
  .tool_input.content //
  .tool_input.new_string //
  ([.tool_input.edits[]?.new_string] | join("\n")) //
  empty
')

[ -z "$content" ] && exit 0

# Skip the check for files that legitimately contain examples or documentation.
# Be specific about which markdown files are exempt — a stray `.md` in the code
# folder shouldn't be a free pass for a hardcoded token.
case "$file_path" in
  */README*.md|*/README|*/CHANGELOG*.md|*/CHANGELOG|*.example|*.example.*|*.sample|*.sample.*|*example*.md) exit 0 ;;
esac

# Token patterns. Each is well-known and high-entropy enough to rarely false-positive.
patterns=(
  'AKIA[0-9A-Z]{16}'                           # AWS access key id
  'ASIA[0-9A-Z]{16}'                           # AWS temporary session token
  'gh[poasu]_[A-Za-z0-9]{30,}'                 # GitHub PAT/OAuth/server/user tokens
  'sk-(ant-|proj-|live-|admin-)?[A-Za-z0-9_-]{20,}'  # OpenAI / Anthropic / admin keys
  'sk_(live|test)_[A-Za-z0-9]{20,}'            # Stripe secret keys
  'rk_(live|test)_[A-Za-z0-9]{20,}'            # Stripe restricted keys
  'xox[baprs]-[A-Za-z0-9-]{10,}'               # Slack
  'AIza[0-9A-Za-z_-]{35}'                      # Google API
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'         # PEM private keys (RSA, EC, OpenSSH, …)
)

# Build a single ERE alternation from the array.
pattern=$(IFS='|'; echo "${patterns[*]}")

matches=$(echo "$content" | grep -nE "$pattern" | head -3)

if [ -n "$matches" ]; then
  echo "Blocked: this content looks like it contains a hardcoded secret/token. Move it to an env var or a gitignored config file." >&2
  echo "Match preview: $matches" >&2
  exit 2
fi

exit 0
