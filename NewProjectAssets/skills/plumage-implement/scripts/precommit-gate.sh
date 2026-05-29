#!/usr/bin/env bash
# precommit-gate.sh — run the 7-check pre-commit gate.
#
# Used by both the /plumage-implement skill (after the last task) and Plumage's native
# "Run Quality Gate" toolbar button (no agent involved). Same checks, same
# order, same exit semantics.
#
# Usage:
#   scripts/precommit-gate.sh [--first-commit] [--skip-build] [--skip-tests]
#                             [--skip-uitests] [--close-instances]
#
# Flags:
#   --first-commit   Also run the .gitignore sanity check (step 7).
#                    Caller decides — the script can't reliably tell if this
#                    is "the issue's first commit on the branch" on its own.
#   --skip-build     Skip step 1 (e.g., when the caller has already verified
#                    the build via a higher-fidelity tool like XcodeBuildMCP).
#   --skip-tests     Skip step 2.
#   --skip-uitests   Exclude *UITests targets from the test run (step 2). A
#                    running app instance wedges the UI-test launch; this avoids
#                    the hang without touching the instance.
#   --close-instances  If the app under test is already running, close it (and
#                    any debugserver holding it) before testing, then run the
#                    full suite. Without this flag, a running instance is handled
#                    interactively (prompt on a TTY) or by skipping UI tests
#                    (non-interactive — never auto-kills, since this script also
#                    runs from the app's own toolbar and would self-kill).
#
# Output:
#   One header line per step:  [N/7] <name>... <PASS|FAIL|SKIP>
#   On FAIL, an indented excerpt of the failing output follows.
#   Final line:  GATE PASSED  or  GATE FAILED (N failures)
#
# Exit codes:
#   0  all checks passed (or skipped)
#   1  at least one check failed
#   2  environment problem (missing tools, not in a git repo, no Swift project)

set -uo pipefail

# ---- Argument parsing -------------------------------------------------------

first_commit=0
skip_build=0
skip_tests=0
skip_tests_reason="--skip-tests"
skip_uitests=0
close_instances=0

for arg in "$@"; do
    case "$arg" in
        --first-commit)    first_commit=1    ;;
        --skip-build)      skip_build=1      ;;
        --skip-tests)      skip_tests=1      ;;
        --skip-uitests)    skip_uitests=1    ;;
        --close-instances) close_instances=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown flag: $arg" >&2
            exit 2
            ;;
    esac
done

# ---- Environment checks -----------------------------------------------------

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo_root" ]; then
    echo "error: not inside a git repository" >&2
    exit 2
fi
cd "$repo_root"

# Detect project type. Decides build/test commands; doesn't affect later steps.
project_type="unknown"
if [ -f Package.swift ]; then
    project_type="swiftpm"
elif find . -maxdepth 3 -name "*.xcworkspace" -not -path "*/.*" 2>/dev/null | grep -q .; then
    project_type="xcworkspace"
elif find . -maxdepth 3 -name "*.xcodeproj" -not -path "*/.*" 2>/dev/null | grep -q .; then
    project_type="xcodeproj"
fi

# Resolve scheme + UI-test targets from a single `xcodebuild -list` call.
# Reused by the running-instance check, the build step, and the test step
# (each previously re-ran `-list`).
scheme=""
uitest_targets=()
if [ "$project_type" = "xcodeproj" ] || [ "$project_type" = "xcworkspace" ]; then
    xclist=$(xcodebuild -list 2>/dev/null || true)
    scheme=$(printf '%s\n' "$xclist" \
        | awk '/Schemes:/{flag=1; next} flag && NF{print $1; exit}')
    while IFS= read -r uit; do
        [ -n "$uit" ] && uitest_targets+=("$uit")
    done < <(printf '%s\n' "$xclist" \
        | awk '/Targets:/{f=1; next} /Build Configurations:|Schemes:/{f=0} f && NF{print $1}' \
        | grep -iE 'UITests$' || true)
fi

# ---- Running-instance handling (GUI app) ------------------------------------
#
# A *running* instance of the app under test wedges xcodebuild's test launch.
# Both the UI-test target AND the hosted unit-test runner go through the same
# launch / testmanagerd coordination, so skipping only the UI tests is NOT
# enough — the hosted unit-test run hangs too. The usual culprit is a leftover
# Xcode Run/debug session: the app held under `debugserver`, stuck in state SX
# and ignoring SIGKILL until the debugger is detached. Decide before the test
# step:
#   - --close-instances       -> close them (incl. a holding debugserver), full run
#   - interactive TTY         -> ask whether to close
#   - non-interactive/no flag -> SKIP the whole test step (NEVER auto-kill: this
#     script also runs from the app's own toolbar and would otherwise self-kill)
#
# pgrep pattern matches `<scheme>.app/Contents/MacOS/` (any executable inside),
# not `<scheme>.app/Contents/MacOS/<scheme>`, so projects whose EXECUTABLE_NAME
# differs from the scheme name are still caught. No-ops for non-.app products.

tests_skipped_due_to_instance=0

if [ $skip_tests -eq 0 ] && [ -n "$scheme" ]; then
    running_pids=$(pgrep -f "${scheme}.app/Contents/MacOS/" 2>/dev/null || true)
    if [ -n "$running_pids" ]; then
        pid_list=$(printf '%s' "$running_pids" | tr '\n' ' ')
        decision=""
        if [ $close_instances -eq 1 ]; then
            decision="close"
        elif [ -t 0 ] && [ -t 1 ]; then
            printf '%s is running (pids: %s) and will wedge the test run.\n' "$scheme" "$pid_list" >&2
            printf 'Close it and run the full test suite? [y/N] ' >&2
            read -r answer
            case "$answer" in
                [yY]|[yY][eE][sS]) decision="close" ;;
                *)                 decision="skip"  ;;
            esac
        else
            decision="skip"
        fi

        if [ "$decision" = "close" ]; then
            for pid in $running_pids; do
                ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
                if [ -n "$ppid" ]; then
                    pcmd=$(ps -o comm= -p "$ppid" 2>/dev/null || true)
                    case "$pcmd" in *debugserver*) kill "$ppid" 2>/dev/null || true ;; esac
                fi
                kill "$pid" 2>/dev/null || true
            done
            sleep 2
            for pid in $running_pids; do kill -9 "$pid" 2>/dev/null || true; done
            sleep 1
            if pgrep -f "${scheme}.app/Contents/MacOS/" >/dev/null 2>&1; then
                skip_tests=1
                skip_tests_reason="$scheme still running after close (orphaned/stuck — reboot may be needed)"
                tests_skipped_due_to_instance=1
            fi
        else
            skip_tests=1
            skip_tests_reason="$scheme is running; close it or pass --close-instances"
            tests_skipped_due_to_instance=1
        fi
    fi
fi

failures=0
step=0
total=7

# ---- Reporting helpers ------------------------------------------------------

# print_result <pass|fail|skip> [reason]
print_result() {
    local status="$1"
    case "$status" in
        pass) printf 'PASS\n' ;;
        skip) printf 'SKIP%s\n' "${2:+ ($2)}" ;;
        fail) printf 'FAIL\n'; failures=$((failures + 1)) ;;
    esac
}

# print_excerpt <log-file> — indent and trim the last ~20 lines for the user.
print_excerpt() {
    local log="$1"
    [ -s "$log" ] || return 0
    tail -20 "$log" | sed 's/^/    /'
}

start_step() {
    step=$((step + 1))
    printf '[%d/%d] %s... ' "$step" "$total" "$1"
}

tmplog=$(mktemp)
trap 'rm -f "$tmplog"' EXIT

# ---- Step 1: Build ----------------------------------------------------------
#
# Warning policy: if Package.swift sets `.treatAllWarnings(as: .error)` (or the
# Xcode project sets SWIFT_TREAT_WARNINGS_AS_ERRORS=YES), warnings already
# fail the build at compile time and the grep below is a no-op. The grep is
# the fallback for projects that don't opt into compile-time strictness.
# It's fragile against pretty-printers (xcbeautify, xcpretty) — see
# precommit-gate.md for guidance.

start_step "Build (zero errors, zero warnings)"

if [ $skip_build -eq 1 ]; then
    print_result skip "--skip-build"
else
    case "$project_type" in
        swiftpm)
            if swift build > "$tmplog" 2>&1; then
                # Build succeeded. Now check for warnings — `swift build` doesn't
                # fail on those by default. Look for ": warning:" anchors.
                if grep -q ': warning:' "$tmplog"; then
                    print_result fail
                    grep ': warning:' "$tmplog" | head -10 | sed 's/^/    /'
                else
                    print_result pass
                fi
            else
                print_result fail
                print_excerpt "$tmplog"
            fi
            ;;
        xcworkspace|xcodeproj)
            # Scheme already resolved at the top from a single `xcodebuild -list`
            # (picks the first one alphabetically). Most projects have a single
            # primary scheme; complex cases should use --skip-build and drive
            # xcodebuild directly.
            if [ -z "$scheme" ]; then
                print_result fail
                echo "    couldn't determine scheme; pass --skip-build and drive xcodebuild yourself"
            else
                if xcodebuild -scheme "$scheme" build > "$tmplog" 2>&1; then
                    if grep -q ': warning:' "$tmplog"; then
                        print_result fail
                        grep ': warning:' "$tmplog" | head -10 | sed 's/^/    /'
                    else
                        print_result pass
                    fi
                else
                    print_result fail
                    print_excerpt "$tmplog"
                fi
            fi
            ;;
        *)
            print_result skip "no Swift project detected"
            ;;
    esac
fi

# ---- Step 2: Tests ----------------------------------------------------------

start_step "Tests"

if [ $skip_tests -eq 1 ]; then
    print_result skip "$skip_tests_reason"
else
    case "$project_type" in
        swiftpm)
            # Detect whether the project has any tests at all. A clean SwiftPM
            # project without Tests/ should skip without failing.
            if [ -d Tests ] && find Tests -maxdepth 3 -name "*Tests.swift" -o -name "*Test.swift" 2>/dev/null | grep -q .; then
                if swift test > "$tmplog" 2>&1; then
                    print_result pass
                else
                    print_result fail
                    print_excerpt "$tmplog"
                fi
            else
                print_result skip "no tests in project"
            fi
            ;;
        xcworkspace|xcodeproj)
            if [ -n "$scheme" ]; then
                # Exclude *UITests targets when --skip-uitests is passed
                # explicitly. Space-joined, no spaces in target names, so
                # unquoted expansion is safe on bash 3.2.
                skip_flags=""
                if [ $skip_uitests -eq 1 ] && [ ${#uitest_targets[@]} -gt 0 ]; then
                    for uit in "${uitest_targets[@]}"; do
                        skip_flags="$skip_flags -skip-testing:$uit"
                    done
                fi
                if xcodebuild -scheme "$scheme" test $skip_flags > "$tmplog" 2>&1; then
                    if [ -n "$skip_flags" ]; then
                        print_result pass
                        printf '    (skipped:%s)\n' "$skip_flags"
                    else
                        print_result pass
                    fi
                else
                    print_result fail
                    print_excerpt "$tmplog"
                fi
            else
                print_result skip "no scheme detected"
            fi
            ;;
        *)
            print_result skip "no Swift project detected"
            ;;
    esac
fi

# ---- Step 3: SwiftLint ------------------------------------------------------

start_step "SwiftLint (zero violations)"

if ! command -v swiftlint >/dev/null 2>&1; then
    print_result skip "swiftlint not installed"
else
    if swiftlint --strict --quiet > "$tmplog" 2>&1; then
        print_result pass
    else
        print_result fail
        print_excerpt "$tmplog"
    fi
fi

# ---- Step 4: swift-format lint ---------------------------------------------

start_step "swift-format (lint mode)"

if ! command -v swift-format >/dev/null 2>&1; then
    print_result skip "swift-format not installed"
else
    # Find Swift sources to lint. Exclude common build/derived directories.
    if find . -name "*.swift" -not -path "./.build/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*" -print0 2>/dev/null \
        | xargs -0 swift-format lint --strict > "$tmplog" 2>&1; then
        print_result pass
    else
        print_result fail
        print_excerpt "$tmplog"
    fi
fi

# ---- Step 5: git status — no untracked secret files ------------------------

start_step "Untracked secrets check (git status)"

# Use a single regex that matches the well-known secret-file shapes.
secret_pattern='(^|/)(\.env(\..+)?|.*\.key|.*\.pem|id_rsa|id_ed25519|id_ecdsa|aws-credentials|\.netrc)$'

untracked_secrets=$(git status --porcelain 2>/dev/null \
    | awk '$1 == "??" { print $2 }' \
    | grep -E "$secret_pattern" || true)

if [ -n "$untracked_secrets" ]; then
    print_result fail
    echo "$untracked_secrets" | sed 's/^/    /'
else
    print_result pass
fi

# ---- Step 6: git diff — no hardcoded secrets in diff -----------------------

start_step "Hardcoded secrets check (git diff)"

# Determine the default branch. Try `git.defaultBranch` from config, fall back
# to `main` then `master`.
default_branch=""
if [ -f .plumage/config.json ] && command -v jq >/dev/null 2>&1; then
    default_branch=$(jq -r '.git.defaultBranch // empty' .plumage/config.json 2>/dev/null || true)
fi
if [ -z "$default_branch" ]; then
    if git show-ref --verify --quiet refs/heads/main; then
        default_branch=main
    elif git show-ref --verify --quiet refs/heads/master; then
        default_branch=master
    fi
fi

if [ -z "$default_branch" ]; then
    print_result skip "no default branch found (main/master)"
else
    # Conservative secret patterns: well-known prefixes that virtually never
    # appear in legitimate non-test code.
    diff_secrets=$(git diff "${default_branch}...HEAD" 2>/dev/null | grep -E \
        -e 'AKIA[0-9A-Z]{16}' \
        -e 'ghp_[A-Za-z0-9]{36}' \
        -e 'sk-[A-Za-z0-9]{32,}' \
        -e 'sk-ant-[A-Za-z0-9_-]{20,}' \
        -e 'xox[baprs]-[A-Za-z0-9-]+' \
        -e 'AIza[0-9A-Za-z_-]{35}' \
        || true)
    if [ -n "$diff_secrets" ]; then
        print_result fail
        echo "$diff_secrets" | head -10 | sed 's/^/    /'
    else
        print_result pass
    fi
fi

# ---- Step 7: .gitignore sanity (first commit only) -------------------------

start_step ".gitignore sanity"

if [ $first_commit -eq 0 ]; then
    print_result skip "not first commit"
else
    if [ ! -f .gitignore ]; then
        print_result fail
        echo "    .gitignore is missing"
    else
        missing=()
        case "$project_type" in
            swiftpm)
                grep -qE '^\.build/?' .gitignore || missing+=(".build/")
                grep -qE '^\.swiftpm/?' .gitignore || missing+=(".swiftpm/")
                ;;
            xcworkspace|xcodeproj)
                grep -qE '^DerivedData/?' .gitignore || missing+=("DerivedData/")
                grep -qE 'xcuserdata' .gitignore || missing+=("xcuserdata/")
                ;;
        esac
        if [ ${#missing[@]} -eq 0 ]; then
            print_result pass
        else
            print_result fail
            printf '    missing: %s\n' "${missing[@]}"
        fi
    fi
fi

# ---- Summary ----------------------------------------------------------------

echo
if [ $failures -eq 0 ]; then
    if [ $tests_skipped_due_to_instance -eq 1 ]; then
        # Loud about the skip so a green PASS line isn't read as "tests passed":
        # the toolbar invocation (script runs from within the running app) always
        # lands here, and `/plumage-implement` without --close-instances would too.
        echo "GATE PASSED — but tests were SKIPPED ($skip_tests_reason)"
    else
        echo "GATE PASSED"
    fi
    exit 0
else
    echo "GATE FAILED ($failures failure$([ $failures -ne 1 ] && echo s))"
    exit 1
fi
