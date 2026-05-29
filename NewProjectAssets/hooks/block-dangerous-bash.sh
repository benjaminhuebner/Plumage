#!/usr/bin/env bash
# block-dangerous-bash.sh — PreToolUse hook
#
# Blocks obviously destructive bash commands. Conservative — only patterns
# that are virtually never legitimate from an agent. The user can always
# run them themselves outside Claude.
#
# Wired up via .claude/settings.json:
#
#   "PreToolUse": [
#     {
#       "matcher": "Bash",
#       "hooks": [
#         { "type": "command",
#           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-bash.sh" }
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
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

block() {
  echo "Blocked: this command pattern is destructive ($1). If you really need it, ask the user to run it." >&2
  exit 2
}

# 1. rm -rf hitting protected paths.
# Extract the first non-flag argument after `rm -rf` (or `-fr`, `-rfv`, etc.).
if echo "$cmd" | grep -qE '\brm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*[[:space:]]+'; then
  # Pull the first arg after the flags.
  target=$(echo "$cmd" \
    | sed -nE 's/.*\brm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*[[:space:]]+([^[:space:];&|]+).*/\1/p' \
    | head -n1)
  # Patterns cover BOTH literal forms (`$HOME`, `~`) — passed through unevaluated —
  # AND the expanded path that the shell would produce. Without "$HOME" patterns,
  # `rm -rf /Users/foo` (expanded by Claude) would slip through.
  case "$target" in
    # Wipe of home, project, or root — literal and expanded
    '/'|'~'|'.'|'./'|'$HOME'|"$HOME")
      block "rm -rf of a top-level path: $target" ;;
    # Anything inside home — literal and expanded
    '~/'*|'$HOME/'*|"$HOME"/*)
      block "rm -rf inside the user's home: $target" ;;
    # System paths — never the agent's job to delete from these
    /etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/var|/var/*|/opt|/opt/*|/root|/root/*|/boot|/boot/*|/System|/System/*|/Library|/Library/*)
      block "rm -rf of a system path: $target" ;;
  esac
fi

# 2. chmod -R 777 hitting top-level paths.
if echo "$cmd" | grep -qE '\bchmod[[:space:]]+-R?[[:space:]]+777[[:space:]]+'; then
  target=$(echo "$cmd" \
    | sed -nE 's/.*\bchmod[[:space:]]+-R?[[:space:]]+777[[:space:]]+([^[:space:];&|]+).*/\1/p' \
    | head -n1)
  case "$target" in
    '/'|'~'|'.'|'./'|'$HOME'|"$HOME"|'~/'*|'$HOME/'*|"$HOME"/*)
      block "chmod -R 777 of a top-level path: $target" ;;
  esac
fi

# 3. find … -delete from a top-level path.
if echo "$cmd" | grep -qE '\bfind[[:space:]]+'; then
  target=$(echo "$cmd" \
    | sed -nE 's/.*\bfind[[:space:]]+([^[:space:];&|]+).*/\1/p' \
    | head -n1)
  if echo "$cmd" | grep -qE '\-delete\b'; then
    case "$target" in
      '/'|'~'|'$HOME'|"$HOME"|'~/'*|'$HOME/'*|"$HOME"/*)
        block "find -delete from a top-level path: $target" ;;
    esac
  fi
fi

# 4. Pattern-based blocks that don't depend on a target arg.
declare -a patterns=(
  ':\(\)\{:\|:&\};:'                        # classic fork bomb
  '>[[:space:]]*/dev/(sd[a-z]|nvme|disk)'  # write to raw block device
  '\bmkfs(\.|[[:space:]])'                  # filesystem creation
  'dd[[:space:]]+if=.*of=/dev/(sd[a-z]|nvme|disk)'  # dd to a device
  '\bsudo[[:space:]]+rm[[:space:]]'         # sudo rm — virtually never legit
)

for p in "${patterns[@]}"; do
  if echo "$cmd" | grep -qE "$p"; then
    block "matched pattern: $p"
  fi
done

exit 0
