#!/usr/bin/env bash
# no-doc-comments.sh — PreToolUse hook
#
# Blocks Write/Edit/MultiEdit calls that introduce *new* documentation
# comments (`///`, `//!`, `/** */`, Python docstrings) on types, methods,
# classes, structs, or properties — unless the user has explicitly asked for
# documentation in a recent turn.
#
# Diff-aware: pre-existing doc comments that survive an edit unchanged are
# ignored. Only newly added (or modified) doc comments cause a block.
#   - Write: compares the new content against the file's current on-disk state.
#   - Edit/MultiEdit: compares new_string against old_string.
#
# Design philosophy: fail OPEN on internal hook errors (missing dep, malformed
# input, regex hiccup). The failure mode here is "one doc comment slips through"
# — recoverable, and the pre-commit gate is the backstop. Blocking a legit edit
# because the hook itself broke would be worse. Contrast with block-secret-files.sh
# which fails closed because its failure mode is "leak a secret".
#
# Block mechanism: exit 2 with stderr feedback. Claude sees the feedback and
# retries without docs. The user sees nothing.
#
# Dependencies: bash 3.2+, jq, perl (perl ships with macOS and most Linux distros).
#
# Wired up via .claude/settings.json:
#
#   "PreToolUse": [
#     {
#       "matcher": "Write|Edit|MultiEdit",
#       "hooks": [
#         { "type": "command",
#           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/no-doc-comments.sh" }
#       ]
#     }
#   ]

set -uo pipefail

# --- Dependencies --------------------------------------------------------
# Fail open: if jq or perl isn't installed, let the action through silently.
# This hook is a policy convenience, not a safety gate.

command -v jq   >/dev/null 2>&1 || exit 0
command -v perl >/dev/null 2>&1 || exit 0

# --- Read tool input -----------------------------------------------------

input=$(cat)
[ -z "$input" ] && exit 0

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
case "$tool_name" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

# --- Filter by file extension (code only) --------------------------------

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
if [ -n "$file_path" ]; then
  lc_path=$(printf '%s' "$file_path" | tr '[:upper:]' '[:lower:]')
  case "$lc_path" in
    *.swift|*.py|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.rs|*.go|*.java|*.kt|*.kts|*.scala|\
*.c|*.h|*.cpp|*.hpp|*.cc|*.cxx|*.cs|*.dart|*.rb|*.php|*.m|*.mm|*.lua)
      ;;
    *) exit 0 ;;
  esac
fi

# --- Extract old and new content into temp files -------------------------

old_file=$(mktemp 2>/dev/null) || exit 0
new_file=$(mktemp 2>/dev/null) || { rm -f "$old_file"; exit 0; }
trap 'rm -f "$old_file" "$new_file"' EXIT

case "$tool_name" in
  Write)
    echo "$input" | jq -j '.tool_input.content // ""' > "$new_file" 2>/dev/null
    if [ -n "$file_path" ] && [ -f "$file_path" ]; then
      cat "$file_path" > "$old_file" 2>/dev/null || true
    fi
    ;;
  Edit)
    echo "$input" | jq -j '.tool_input.old_string // ""' > "$old_file" 2>/dev/null
    echo "$input" | jq -j '.tool_input.new_string // ""' > "$new_file" 2>/dev/null
    ;;
  MultiEdit)
    echo "$input" | jq -j '[.tool_input.edits[]? | .old_string // ""] | join("\n")' > "$old_file" 2>/dev/null
    echo "$input" | jq -j '[.tool_input.edits[]? | .new_string // ""] | join("\n")' > "$new_file" 2>/dev/null
    ;;
esac

# --- Find newly-added doc comments ---------------------------------------
# Patterns are conservative to avoid false positives on banners like //// or
# /******/. Each pattern fires once per match-class — we don't need a full
# count, just the names of conventions that newly appeared in the diff.
#
# Perl heredoc is wrapped in a function so bash 3.2 (macOS default) parses
# the closing `)` of `$(...)` correctly. Without the wrapper, bash 3.2 fails
# with "unexpected EOF while looking for matching `)'".

scan_for_new_docs() {
    perl - "$old_file" "$new_file" <<'PERL'
use strict;
use warnings;

my ($old_path, $new_path) = @ARGV;

sub slurp {
    my $path = shift;
    open(my $fh, '<', $path) or return '';
    local $/;
    my $content = <$fh>;
    close $fh;
    return defined($content) ? $content : '';
}

my $old = slurp($old_path);
my $new = slurp($new_path);
exit 0 unless length $new;

my @patterns = (
    [ qr{^[ \t]*///(?!/)}m,                    "/// doc comment" ],
    [ qr{^[ \t]*//!}m,                          "//! inner doc comment" ],
    [ qr{/\*\*(?!\*)[\s\S]*?\*/},               "/** ... */ doc comment" ],
    [ qr{^[ \t]*(?:async\s+)?(?:def|class)\s+[^\n]+:[ \t]*(?:\n[ \t]*\@[^\n]+)*\n[ \t]+[rbuRBU]{0,2}(?:"{3}|'{3})}m,
      "Python docstring on def/class" ],
    [ qr{\A\s*(?:\#![^\n]*\n)?\s*[rbuRBU]{0,2}(?:"{3}|'{3})},
      "Python module docstring" ],
);

my %hits;
for my $p (@patterns) {
    my ($re, $label) = @$p;
    while ($new =~ /$re/g) {
        my $match = $&;
        if (index($old, $match) == -1) {
            $hits{$label} = 1;
            last;  # one hit per pattern is enough
        }
    }
}
print join(", ", sort keys %hits) if %hits;
PERL
}

hits=$(scan_for_new_docs)

# No new doc comments — let it through.
[ -z "$hits" ] && exit 0

# --- Opt-in: check recent user messages for permission keywords ----------
# If the user explicitly asked for docs in the last few turns, let it through.
# Keywords are deliberately specific — "doc" alone would trigger on things
# like "doctest" or "Dockerfile".

transcript=$(echo "$input" | jq -r '.transcript_path // empty')
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    recent=$(jq -rs '
        [ .[]
          | select(.type == "user")
          | .message.content
          | if type == "string" then .
            elif type == "array" then
                [ .[]? | select(.type == "text") | .text ] | join("\n")
            else "" end
        ] | .[-5:] | join("\n") | ascii_downcase
    ' "$transcript" 2>/dev/null || echo "")

    if [ -n "$recent" ]; then
        for kw in \
            "docstring" "doc comment" \
            "document this" "document the" "document each" "document every" \
            "add docs" "with docs" "include docs" \
            "javadoc" "jsdoc" "rustdoc" "tsdoc" "kdoc" \
            "dokumentier"; do
            if printf '%s' "$recent" | grep -qF -- "$kw"; then
                exit 0
            fi
        done
    fi
fi

# --- Block ---------------------------------------------------------------

cat >&2 <<EOF
Blocked: this change introduces documentation comments ($hits).

Project policy: no doc comments on types, methods, classes, structs, or properties unless the user explicitly asked for them in this turn — even if the signature seems unclear. Inline comments that explain a non-obvious *why* (workaround, perf trade-off, surprising behavior) are still fine; don't restate code, don't write owner-less TODOs.

Rewrite the change without the doc comments. If the user did ask for docs and this hook fired anyway, mention it — there's an opt-in keyword path in the hook source.
EOF
exit 2
