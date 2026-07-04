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

# 1. rm with recursive+force hitting protected paths. Flags are parsed per
# token so `-fr`, `-rf`, `-Rf`, `-r -f`, and `--recursive --force` all count,
# in any order; every target argument is checked, not just the first.
check_rm() {
  local recursive=0 force=0 flags_done=0 targets='' tok t
  for tok in "$@"; do
    if [ "$flags_done" -eq 0 ]; then
      case "$tok" in
        --) flags_done=1; continue ;;
        --recursive) recursive=1; continue ;;
        --force) force=1; continue ;;
        --*) continue ;;
        -?*)
          case "$tok" in *[rR]*) recursive=1 ;; esac
          case "$tok" in *f*) force=1 ;; esac
          continue ;;
      esac
    fi
    targets="$targets $tok"
  done
  { [ "$recursive" -eq 1 ] && [ "$force" -eq 1 ]; } || return 0
  # Patterns cover BOTH literal forms (`$HOME`, `~`) — passed through unevaluated —
  # AND the expanded path that the shell would produce. Without "$HOME" patterns,
  # `rm -rf /Users/foo` (expanded by Claude) would slip through.
  for t in $targets; do
    case "$t" in
      # Wipe of home, project, parent, or root — literal and expanded.
      # Globbing is off while tokenizing, so '/*' arrives literally.
      '/'|'/*'|'~'|'.'|'./'|'..'|'../'|'$HOME'|"$HOME")
        block "rm -rf of a top-level path: $t" ;;
      # Anything inside home — literal and expanded
      '~/'*|'$HOME/'*|"$HOME"/*)
        block "rm -rf inside the user's home: $t" ;;
      # System paths — never the agent's job to delete from these
      /etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/var|/var/*|/opt|/opt/*|/root|/root/*|/boot|/boot/*|/System|/System/*|/Library|/Library/*)
        block "rm -rf of a system path: $t" ;;
    esac
  done
}

# 2. chmod -R 777 hitting top-level paths. Recursive flag detected in any
# position or combination (`-R`, `-vR`, `--recursive`); all targets checked.
check_chmod() {
  local recursive=0 flags_done=0 mode='' targets='' tok t
  for tok in "$@"; do
    if [ "$flags_done" -eq 0 ]; then
      case "$tok" in
        --) flags_done=1; continue ;;
        --recursive) recursive=1; continue ;;
        --*) continue ;;
        -?*) case "$tok" in *R*) recursive=1 ;; esac; continue ;;
      esac
    fi
    if [ -z "$mode" ]; then mode=$tok; continue; fi
    targets="$targets $tok"
  done
  [ "$recursive" -eq 1 ] || return 0
  case "$mode" in 777|0777) ;; *) return 0 ;; esac
  for t in $targets; do
    case "$t" in
      '/'|'~'|'.'|'./'|'$HOME'|"$HOME"|'~/'*|'$HOME/'*|"$HOME"/*)
        block "chmod -R 777 of a top-level path: $t" ;;
    esac
  done
}

# 3. find … -delete from a top-level path. Leading pre-path option flags
# (-H/-L/-P/…) are skipped; every search root is checked.
check_find() {
  local delete=0 paths_done=0 roots='' tok t
  for tok in "$@"; do
    [ "$tok" = "-delete" ] && delete=1
    if [ "$paths_done" -eq 0 ]; then
      case "$tok" in
        -H|-L|-P|-E|-X|-d|-s|-x) ;;
        -*|\(|!) paths_done=1 ;;
        *) roots="$roots $tok" ;;
      esac
    fi
  done
  [ "$delete" -eq 1 ] || return 0
  for t in $roots; do
    case "$t" in
      '/'|'~'|'..'|'../'|'$HOME'|"$HOME"|'~/'*|'$HOME/'*|"$HOME"/*)
        block "find -delete from a top-level path: $t" ;;
    esac
  done
}

scan_segment() {
  while [ $# -gt 0 ]; do
    case "$1" in
      rm|*/rm) shift; check_rm "$@"; return ;;
      chmod|*/chmod) shift; check_chmod "$@"; return ;;
      find|*/find) shift; check_find "$@"; return ;;
    esac
    shift
  done
  return 0
}

# Split chained commands on separators so `cd x && rm -fr /` is still seen as
# an rm invocation. Globbing stays off while tokenizing so `rm -rf *` doesn't
# expand against the hook's own working directory.
set -f
while IFS= read -r segment; do
  # shellcheck disable=SC2086
  scan_segment $segment
done < <(printf '%s\n' "$cmd" | tr ';|&' '\n')
set +f

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
