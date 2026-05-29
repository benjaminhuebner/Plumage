#!/usr/bin/env bash
# block-secret-files.sh — PreToolUse hook
#
# Blocks Read/Edit/Write/Glob/Grep on sensitive files. Their contents should
# never enter Claude's context, full stop.
#
# macOS only. Requires jq ('brew install jq').
#
# Behavior:
#   - exit 0  -> allow the tool call
#   - exit 2  -> block the tool call (stderr is shown to Claude)
#   - fail closed: any unexpected internal error blocks rather than allows.
#
# Wired up via .claude/settings.json:
#
#   "PreToolUse": [
#     {
#       "matcher": "Read|Edit|Write|Glob|Grep|MultiEdit",
#       "hooks": [
#         { "type": "command",
#           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-secret-files.sh" }
#       ]
#     }
#   ]

# NOTE: This hook uses `set -euo pipefail` plus an ERR trap so that ANY
# unexpected internal failure blocks the tool call instead of allowing it.
# Other hooks use `set -uo pipefail` because their failure mode is "skip the
# nice-to-have"; this one's failure mode is "leak a secret", so it fails closed.
set -euo pipefail

# If anything unexpected goes wrong, block instead of silently letting through.
trap 'echo "Hook error: unexpected failure in $(basename "$0"). Blocking as a precaution." >&2; exit 2' ERR

# Require jq. Without it, JSON parsing fails silently and hooks become useless.
if ! command -v jq >/dev/null 2>&1; then
  echo "Hook error: jq is not installed. Install it (macOS: 'brew install jq') so safety hooks work." >&2
  exit 2
fi

input=$(cat)

# Extract any field that might carry a path or pattern.
# file_path: Read/Edit/Write. path: some tools. pattern: Glob/Grep.
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // empty')

[ -z "$file_path" ] && exit 0

# Normalize to lowercase. APFS is case-insensitive by default on macOS,
# so `ID_RSA` or `.ENV` would otherwise bypass case-sensitive matches.
lc_path=$(printf '%s' "$file_path" | tr '[:upper:]' '[:lower:]')
lc_basename=$(basename "$lc_path")

# If the path is a symlink, also check what it resolves to. Catches tricks
# like `notes.txt -> ~/.aws/credentials`. readlink -f requires macOS 12+.
resolved_lc=""
if [ -L "$file_path" ]; then
  if resolved=$(readlink -f "$file_path" 2>/dev/null); then
    resolved_lc=$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')
  fi
fi

# Whitelist: example/sample/template variants are safe and commonly committed.
case "$lc_basename" in
  .env.example|.env.sample|.env.template|.env.dist|.env.defaults|.env.local.example)
    exit 0 ;;
esac

blocked=0

check_basename() {
  local name="$1"
  case "$name" in
    # Environment files (incl. direnv)
    .env|.env.*|*.env|.envrc|.envrc.*)
      blocked=1 ;;
    # Private keys, keystores, PKCS bundles
    *.pem|*.key|*.p12|*.pfx|*.keystore|*.jks|*.p8)
      blocked=1 ;;
    # GPG / ASCII-armored material (could be private; better safe than sorry)
    *.gpg|*.asc)
      blocked=1 ;;
    # SSH keys by conventional name
    id_rsa|id_ed25519|id_ecdsa|id_dsa|*.ppk)
      blocked=1 ;;
    # Generic secret/credential filenames
    secrets|secrets.*|*.secrets|credentials|credentials.*|.netrc|.pgpass)
      blocked=1 ;;
    # Package manager / registry auth
    .npmrc|.pypirc|.cargo-credentials|.gem/credentials)
      blocked=1 ;;
    # Git credential store
    .git-credentials)
      blocked=1 ;;
    # Apple signing material
    *authkey*.p8|*.mobileprovision)
      blocked=1 ;;
    # Terraform state (routinely contains plaintext secrets)
    terraform.tfstate|*.tfstate|*.tfstate.*|*.tfstate.backup)
      blocked=1 ;;
    # Web server auth
    htpasswd|.htpasswd)
      blocked=1 ;;
    # Crypto wallets / password DBs
    wallet.dat|*.wallet|*.kdbx|*.kdb)
      blocked=1 ;;
  esac
}

check_path() {
  local p="$1"
  case "$p" in
    */.ssh/*|\
    */.aws/*|\
    */.gnupg/*|\
    */.config/gh/*|\
    */.config/gcloud/*|\
    */.kube/*|\
    */.docker/config.json*|\
    */library/keychains/*|\
    */library/application?support/*/login*)
      blocked=1 ;;
  esac
}

check_basename "$lc_basename"
check_path "$lc_path"

# Re-check against the symlink target if present.
if [ -n "$resolved_lc" ]; then
  check_basename "$(basename "$resolved_lc")"
  check_path "$resolved_lc"
fi

# Glob/Grep patterns can target secrets without their basename matching above.
# `**/.env*` has basename `.env*` which the case statements DO catch, but
# broader patterns like `**/*` won't. So if the input looks like a glob
# (contains * or ?) AND mentions a sensitive token, flag it.
case "$file_path" in
  *\**|*\?*)
    case "$lc_path" in
      *.env*|*secret*|*credential*|*/.ssh*|*/.aws*|*private*key*|*id_rsa*|*id_ed25519*|*.pem*|*.tfstate*)
        blocked=1 ;;
    esac
    ;;
esac

if [ "$blocked" = "1" ]; then
  echo "Blocked: \"$file_path\" looks like a secret/credential file or matches a sensitive path. Don't read or modify it. If you need a value from it, ask the user to provide it directly." >&2
  exit 2
fi

exit 0