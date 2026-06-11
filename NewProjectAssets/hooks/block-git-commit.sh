#!/usr/bin/env bash
# block-git-commit.sh — PreToolUse hook
#
# Git safety:
#   - `git push` and `git tag` are always blocked.
#   - `git commit` is blocked on protected branches (main, master),
#     in detached HEAD, on unborn branches pointing at main/master,
#     and when no git repo can be located.
#   - Anything else is allowed.
#
# Design philosophy: fail CLOSED on ambiguity. One false block beats one
# accidental commit on main or an unintended push.
#
# Wired up via .claude/settings.json:
#
#   "PreToolUse": [
#     {
#       "matcher": "Bash",
#       "hooks": [
#         { "type": "command",
#           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-git-commit.sh" }
#       ]
#     }
#   ]

set -uo pipefail

# --- Dependencies --------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  echo "Hook error: jq is not installed. Install it (macOS: 'brew install jq') so safety hooks work." >&2
  exit 2
fi

# --- Read tool input -----------------------------------------------------

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -z "$command" ]] && exit 0

# Quick filter: bail out unless `git` appears as a word in the command.
# The character class catches env-prefixed (`GIT_DIR=… git`), chained
# (`… && git`, `… ; git`, `… | git`), and subshelled (`(git`) forms.
if ! echo "$command" | grep -qE '(^|[[:space:];&|=()])git([[:space:]]|$)'; then
  exit 0
fi

# --- Repo discovery ------------------------------------------------------
# In a Plumage project, CLAUDE_PROJECT_DIR is the repo root. `git -C` walks
# up to find the .git dir, so the simple form works for the standard case.
# Falls back to PWD only if CLAUDE_PROJECT_DIR is unset (CLI invocation
# outside of Claude Code).

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
repo_dir=""
if git -C "$project_dir" rev-parse --show-toplevel >/dev/null 2>&1; then
  repo_dir=$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null)
fi

# --- Subcommand extraction -----------------------------------------------

# Blank quoted strings before tokenization: a commit message that *mentions*
# "git push" is not a git push. Quoted invocations (`sh -c "git push"`) become
# a blind spot — accepted; unquoted chained forms still tokenize and block.
strip_quoted() {
  printf '%s' "$1" | tr '\n' ' ' | sed -e 's/"[^"]*"/""/g' -e "s/'[^']*'/''/g"
}

extract_git_subcmds() {
  echo "$1" | awk '
  {
    n = split($0, toks, /[[:space:]]+/)
    i = 1
    while (i <= n) {
      if (toks[i] == "git") {
        skip = 0
        j = i + 1
        while (j <= n) {
          t = toks[j]
          if (skip) { skip = 0; j++; continue }
          if (t ~ /^-/) {
            if ((t == "-C" || t == "-c") && index(t, "=") == 0) skip = 1
            j++; continue
          }
          print t
          break
        }
        i = j + 1
      } else {
        i++
      }
    }
  }'
}

# --- Alias resolution ----------------------------------------------------

resolve_alias() {
  local token="$1" repo="$2" value forbidden

  [[ -z "$repo" ]] && { echo "$token"; return; }

  value=$(git -C "$repo" config --get "alias.$token" 2>/dev/null || echo "")
  [[ -z "$value" ]] && { echo "$token"; return; }

  if [[ "$value" == \!* ]]; then
    for forbidden in push tag commit; do
      if echo "$value" | grep -Eq "(^|[^A-Za-z0-9_])${forbidden}([^A-Za-z0-9_]|$)"; then
        echo "$forbidden"; return
      fi
    done
    echo "$token"
  else
    echo "$value" | awk '{print $1}'
  fi
}

# --- Branch detection ----------------------------------------------------
get_current_branch() {
  local repo="$1" ref
  if ref=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null) && [[ -n "$ref" ]]; then
    echo "$ref"
  else
    echo "HEAD"
  fi
}

# --- Policy enforcement --------------------------------------------------

subcmds=$(extract_git_subcmds "$(strip_quoted "$command")")
[[ -z "$subcmds" ]] && exit 0

while IFS= read -r tok; do
  [[ -z "$tok" ]] && continue

  effective=$(resolve_alias "$tok" "$repo_dir")

  case "$effective" in
    push)
      {
        echo "Blocked: \`git push\` is not allowed. Ask the user to push manually."
        [[ "$effective" != "$tok" ]] && echo "(Resolved from alias: \`$tok\` → \`$effective\`)"
      } >&2
      exit 2 ;;

    tag)
      {
        echo "Blocked: \`git tag\` is not allowed. Tagging is a release operation the user performs manually."
        [[ "$effective" != "$tok" ]] && echo "(Resolved from alias: \`$tok\` → \`$effective\`)"
      } >&2
      exit 2 ;;

    commit)
      if [[ -z "$repo_dir" ]]; then
        echo "Blocked: could not find a git repo from ${project_dir}. Run \`git status\` from the code folder, then retry." >&2
        exit 2
      fi

      branch=$(get_current_branch "$repo_dir")

      if [[ "$branch" == "HEAD" ]]; then
        echo "Blocked: detached HEAD detected. Check out a feature branch before committing." >&2
        exit 2
      fi

      case "$branch" in
        main|master)
          {
            echo "Blocked: refusing to commit on protected branch '$branch'. Create or check out a feature branch first (e.g. \`git checkout -b feature/<slug>\`). If a branch isn't appropriate for this work, suggest a one-sentence commit message to the user and let them run it."
            [[ "$effective" != "$tok" ]] && echo "(Resolved from alias: \`$tok\` → \`$effective\`)"
          } >&2
          exit 2 ;;
      esac
      ;;
  esac
done <<< "$subcmds"

exit 0
