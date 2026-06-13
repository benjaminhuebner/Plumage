#!/usr/bin/env bash
# precommit-gate.sh — two-mode, parallel-track pre-commit gate.
#
# Used by both the /plumage-implement skill and Plumage's native "Run Quality
# Gate" toolbar button (no agent involved). Same checks, same numbered output,
# same exit semantics.
#
# Two modes:
#   default  fast, runs per /plumage-implement task. Skips .integration-tagged
#            suites and the swift-format full-tree sweep (the format hook already
#            covers every edited file). This is the ≤90 s pro-commit gate.
#   --full   comprehensive, runs once at issue end and before merge-local.
#            Includes .integration suites and the swift-format sweep.
#
# Both modes exclude *UITests targets unless --with-uitests is passed.
#
# Usage:
#   scripts/precommit-gate.sh [--full] [--first-commit] [--skip-build]
#                             [--skip-tests] [--with-uitests]
#                             [--close-instances] [--timing] [--wait[=secs]]
#
# Flags:
#   --full           Comprehensive mode (see above). Default is the fast mode.
#   --first-commit   Also run the .gitignore sanity check (step 7).
#   --skip-build     Skip step 1 (e.g. the caller already built via a
#                    higher-fidelity tool). Forces step 2 to `test` instead of
#                    `test-without-building`.
#   --skip-tests     Skip step 2 entirely.
#   --with-uitests   Include *UITests targets in step 2 (opt-in; much slower).
#   --close-instances  If the app under test is running, close it (and any
#                    holding debugserver) before testing. Without it, a running
#                    instance makes the test step SKIP (never auto-kills, since
#                    this script also runs from the app's own toolbar).
#   --timing         Append per-step wallclock " (Xs)" and a "total: Xs" trailer.
#   --wait[=secs]    If a live gate run holds the lock, wait for it to free
#                    (poll every 2 s; default timeout 900 s) instead of failing
#                    fast. On timeout, exit 2 naming the owner PID. Used by
#                    /plumage-implement so gates from parallel worktree runs
#                    queue; the toolbar button keeps the fail-fast default.
#
# Test-plan selection (auto-detected from the repo root):
#   default plan = first  *.xctestplan  that is NOT  *.Full.xctestplan
#   full plan    = first  *.Full.xctestplan
#   If no plan is found, the test step falls back to an unfiltered run.
#   .integration suites are excluded in default mode via -skip-testing flags
#   derived from the `.tags(.integration)` annotations (xcodebuild does not
#   honour Swift Testing tag/skip selection inside .xctestplan files — see
#   precommit-gate.md). These derived flags are the single source of truth for
#   the exclusion; the test plans carry no manual skip list.
#
# Output:
#   One header line per step:  [N/7] <name>... <PASS|FAIL|SKIP>
#   On FAIL, an indented excerpt of the failing output follows.
#   Final line:  GATE PASSED  or  GATE FAILED (N failures)
#
# Exit codes:
#   0  all checks passed (or skipped)
#   1  at least one check failed
#   2  environment problem (missing tools, not in a git repo, no Swift project,
#      or a live gate run holds the lock — the lock is shared across all
#      worktrees of the repo; a lock whose owner is dead is taken over)

set -uo pipefail

# ---- Argument parsing -------------------------------------------------------

full=0
first_commit=0
skip_build=0
skip_tests=0
skip_tests_reason="--skip-tests"
skip_uitests=1
close_instances=0
timing=0
wait_for_lock=0
wait_secs=900

for arg in "$@"; do
    case "$arg" in
        --full)            full=1            ;;
        --first-commit)    first_commit=1    ;;
        --skip-build)      skip_build=1      ;;
        --skip-tests)      skip_tests=1      ;;
        --with-uitests)    skip_uitests=0    ;;
        --close-instances) close_instances=1 ;;
        --timing)          timing=1          ;;
        --wait)            wait_for_lock=1   ;;
        --wait=*)
            wait_for_lock=1
            wait_secs="${arg#--wait=}"
            case "$wait_secs" in
                ''|0|*[!0-9]*)
                    echo "error: --wait expects a positive integer (got: ${wait_secs:-empty})" >&2
                    exit 2
                    ;;
            esac
            ;;
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

# ---- Single-instance lock ---------------------------------------------------
#
# The native toolbar button and /plumage-implement runs — including runs in
# other worktrees of the same repo — can all reach this script, so guard with
# the shared lock from lock-lib.sh (also taken by exclusive-lock.sh to keep
# gates away from a manually driven app instance). Sourced before the cd so a
# relative invocation path still resolves.
. "${BASH_SOURCE%/*}/lock-lib.sh"
cd "$repo_root"

if ! try_acquire_lock; then
    if [ $wait_for_lock -eq 1 ]; then
        echo "waiting for gate lock held by PID $lock_owner (timeout ${wait_secs}s)..." >&2
        wait_start=$(date +%s)
        acquired=0
        while [ $(( $(date +%s) - wait_start )) -lt "$wait_secs" ]; do
            sleep 2
            if try_acquire_lock; then acquired=1; break; fi
        done
        if [ $acquired -eq 0 ]; then
            echo "error: gate lock still held by PID $lock_owner after ${wait_secs}s ($lock_file)." >&2
            echo "       if that PID is not a gate run, remove the lock file (PID recycling)." >&2
            exit 2
        fi
    else
        echo "error: another precommit-gate run holds the lock (owner PID $lock_owner, $lock_file)." >&2
        echo "       wait for it to finish or pass --wait to queue behind it;" >&2
        echo "       a lock whose owner has died is taken over automatically." >&2
        exit 2
    fi
fi
trap 'release_lock' EXIT

project_type="unknown"
if [ -f Package.swift ]; then
    project_type="swiftpm"
elif find . -maxdepth 3 -name "*.xcworkspace" -not -path "*/.*" 2>/dev/null | grep -q .; then
    project_type="xcworkspace"
elif find . -maxdepth 3 -name "*.xcodeproj" -not -path "*/.*" 2>/dev/null | grep -q .; then
    project_type="xcodeproj"
fi

# ---- Xcode scheme / target / test-plan / tag discovery ----------------------

scheme=""
unit_test_target=""
uitest_targets=()
app_name=""
default_plan=""
full_plan=""
integration_suites=()

if [ "$project_type" = "xcodeproj" ] || [ "$project_type" = "xcworkspace" ]; then
    xclist=$(xcodebuild -list 2>/dev/null || true)
    scheme=$(printf '%s\n' "$xclist" \
        | awk '/Schemes:/{flag=1; next} flag && NF{print $1; exit}')
    app_name="$scheme"
    # Test targets: a unit target (…Tests, not …UITests) and the UI targets.
    unit_test_target=$(printf '%s\n' "$xclist" \
        | awk '/Targets:/{f=1; next} /Build Configurations:|Schemes:/{f=0} f && NF{print $1}' \
        | grep -iE 'Tests$' | grep -ivE 'UITests$' | head -1)
    while IFS= read -r uit; do
        [ -n "$uit" ] && uitest_targets+=("$uit")
    done < <(printf '%s\n' "$xclist" \
        | awk '/Targets:/{f=1; next} /Build Configurations:|Schemes:/{f=0} f && NF{print $1}' \
        | grep -iE 'UITests$' || true)

    # Test plans (auto-detected by filename convention).
    full_plan=$(ls -1 ./*.Full.xctestplan 2>/dev/null | head -1)
    default_plan=$(ls -1 ./*.xctestplan 2>/dev/null | grep -v '\.Full\.xctestplan$' | sort | head -1)
    full_plan=$(basename "${full_plan%.xctestplan}" 2>/dev/null || true)
    default_plan=$(basename "${default_plan%.xctestplan}" 2>/dev/null || true)

    # .integration-tagged suites, for default-mode -skip-testing. Derived from
    # the annotations so a newly-tagged suite is excluded automatically. Handles
    # multiple tagged suites per file and `struct`/`class`/`final class` forms.
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        while IFS= read -r ln; do
            [ -z "$ln" ] && continue
            name=$(tail -n +"$ln" "$f" | grep -oE '(struct|final class|class) [A-Za-z0-9_]+' | head -1 | awk '{print $NF}')
            [ -n "$name" ] && integration_suites+=("$name")
        done < <(grep -nE 'tags\(\.integration\)' "$f" | cut -d: -f1)
    done < <(grep -rlE 'tags\(\.integration\)' --include='*.swift' . 2>/dev/null \
        | grep -vE '/\.build/|/DerivedData/' || true)

    # Dedupe (a file may yield the same name twice; names never contain spaces).
    if [ ${#integration_suites[@]} -gt 0 ]; then
        integration_suites=($(printf '%s\n' "${integration_suites[@]}" | sort -u))
    fi
fi

# ---- Running-instance handling (GUI app) ------------------------------------
#
# A *running* instance of the app under test wedges xcodebuild's test launch:
# the hosted unit-test runner goes through the same launch/testmanagerd
# coordination as a UI test. The usual culprit is a leftover Xcode Run/debug
# session holding the app under `debugserver`. Decide before the test step.

if [ $skip_tests -eq 0 ] && [ -n "$app_name" ]; then
    running_pids=$(pgrep -f "${app_name}.app/Contents/MacOS/${app_name}" 2>/dev/null || true)
    if [ -n "$running_pids" ]; then
        pid_list=$(printf '%s' "$running_pids" | tr '\n' ' ')
        decision=""
        if [ $close_instances -eq 1 ]; then
            decision="close"
        elif [ -t 0 ] && [ -t 1 ]; then
            printf '%s is running (pids: %s) and will wedge the test run.\n' "$app_name" "$pid_list" >&2
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
            if pgrep -f "${app_name}.app/Contents/MacOS/${app_name}" >/dev/null 2>&1; then
                skip_tests=1
                skip_tests_reason="$app_name still running after close (orphaned/stuck — reboot may be needed)"
            fi
        else
            skip_tests=1
            skip_tests_reason="$app_name is running; close it or pass --close-instances"
        fi
    fi
fi

# ---- Per-step result store (decouples parallel execution from print order) --

work=$(mktemp -d)
trap 'rm -rf "$work"; release_lock' EXIT

# record <step-n> <pass|fail|skip> <seconds> [reason]   (detail excerpt: $work/<n>.detail)
record() {
    printf '%s' "$2" > "$work/$1.status"
    printf '%s' "$3" > "$work/$1.secs"
    [ $# -ge 4 ] && printf '%s' "$4" > "$work/$1.reason"
}

now() { date +%s; }

# ---- Track A: build (step 1) then tests (step 2), sequential ----------------

track_a() {
    local t0 log plan
    log="$work/a.log"

    # Pick the test plan for this mode (used by both build and test steps so the
    # plan-specific .xctestrun exists for test-without-building).
    if [ $full -eq 1 ] && [ -n "$full_plan" ]; then
        plan="$full_plan"
    elif [ $full -eq 0 ] && [ -n "$default_plan" ]; then
        plan="$default_plan"
    else
        plan=""
    fi

    # Step 1: Build
    t0=$(now)
    if [ $skip_build -eq 1 ]; then
        record 1 skip 0 "--skip-build"
    else
        case "$project_type" in
            swiftpm)
                if swift build > "$log" 2>&1; then record 1 pass $(( $(now) - t0 ))
                else record 1 fail $(( $(now) - t0 )); tail -20 "$log" > "$work/1.detail"; fi
                ;;
            xcworkspace|xcodeproj)
                if [ -z "$scheme" ]; then
                    record 1 fail 0
                    echo "couldn't determine scheme; pass --skip-build and drive xcodebuild yourself" > "$work/1.detail"
                else
                    local build_args=(-scheme "$scheme" build-for-testing)
                    [ -n "$plan" ] && build_args+=(-testPlan "$plan")
                    if xcodebuild "${build_args[@]}" > "$log" 2>&1; then
                        record 1 pass $(( $(now) - t0 ))
                    else
                        record 1 fail $(( $(now) - t0 )); tail -20 "$log" > "$work/1.detail"
                    fi
                fi
                ;;
            *) record 1 skip 0 "no Swift project detected" ;;
        esac
    fi

    # Step 2: Tests
    t0=$(now)
    if [ $skip_tests -eq 1 ]; then
        record 2 skip 0 "$skip_tests_reason"
    elif [ -f "$work/1.status" ] && [ "$(cat "$work/1.status")" = "fail" ]; then
        record 2 skip 0 "build failed"
    else
        case "$project_type" in
            swiftpm)
                if [ -d Tests ]; then
                    if swift test > "$log" 2>&1; then record 2 pass $(( $(now) - t0 ))
                    else record 2 fail $(( $(now) - t0 )); tail -20 "$log" > "$work/2.detail"; fi
                else
                    record 2 skip 0 "no tests in project"
                fi
                ;;
            xcworkspace|xcodeproj)
                if [ -z "$scheme" ]; then
                    record 2 skip 0 "no scheme detected"
                else
                    local args=() verb
                    verb="test-without-building"
                    [ $skip_build -eq 1 ] && verb="test"
                    args=(-scheme "$scheme" "$verb")
                    [ -n "$plan" ] && args+=(-testPlan "$plan")
                    # Default mode: exclude .integration suites.
                    if [ $full -eq 0 ] && [ -n "$unit_test_target" ]; then
                        for s in "${integration_suites[@]:-}"; do
                            [ -n "$s" ] && args+=(-skip-testing:"$unit_test_target/$s")
                        done
                    fi
                    # Exclude UITests unless opted in.
                    if [ $skip_uitests -eq 1 ]; then
                        for uit in "${uitest_targets[@]:-}"; do
                            [ -n "$uit" ] && args+=(-skip-testing:"$uit")
                        done
                    fi
                    if xcodebuild "${args[@]}" > "$log" 2>&1; then
                        record 2 pass $(( $(now) - t0 ))
                    else
                        record 2 fail $(( $(now) - t0 )); tail -20 "$log" > "$work/2.detail"
                    fi
                fi
                ;;
            *) record 2 skip 0 "no Swift project detected" ;;
        esac
    fi
}

# ---- Track B: SwiftLint (step 3) + swift-format full sweep (step 4, --full) --

track_b() {
    local t0 log="$work/b.log"

    t0=$(now)
    if ! command -v swiftlint >/dev/null 2>&1; then
        record 3 skip 0 "swiftlint not installed"
    elif swiftlint --strict --quiet > "$log" 2>&1; then
        record 3 pass $(( $(now) - t0 ))
    else
        record 3 fail $(( $(now) - t0 )); tail -20 "$log" > "$work/3.detail"
    fi

    t0=$(now)
    if [ $full -eq 0 ]; then
        record 4 skip 0 "default mode (format hook covers edited files)"
    elif ! command -v swift-format >/dev/null 2>&1; then
        record 4 skip 0 "swift-format not installed"
    else
        # When the bundle is kept out of git, swift-format skips it too (matching
        # SwiftLint). The config flag wins; an older config without it falls back
        # to the bundle-dir line the scaffolder writes into .git/info/exclude.
        local bundle plumage_in_git="" bundle_excluded=0 prune
        bundle=$(find . -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)
        if [ -n "$bundle" ] && command -v jq >/dev/null 2>&1; then
            plumage_in_git=$(jq -r '.git.plumageInGit // empty' "$bundle/config.json" 2>/dev/null)
        fi
        if [ "$plumage_in_git" = "false" ]; then
            bundle_excluded=1
        elif [ "$plumage_in_git" != "true" ] && [ -f .git/info/exclude ] \
            && grep -qE '\.plumage/$' .git/info/exclude; then
            bundle_excluded=1
        fi
        prune=(-not -path "./.build/*" -not -path "./DerivedData/*" -not -path "./.swiftpm/*")
        if [ "$bundle_excluded" -eq 1 ]; then
            prune+=(-not -path "./*.plumage/*")
        fi
        if find . -name "*.swift" "${prune[@]}" -print0 2>/dev/null \
            | xargs -0 swift-format lint --strict > "$log" 2>&1; then
            record 4 pass $(( $(now) - t0 ))
        else
            record 4 fail $(( $(now) - t0 )); tail -20 "$log" > "$work/4.detail"
        fi
    fi
}

# ---- Track C: secret scans (steps 5,6) + .gitignore sanity (step 7) ---------

track_c() {
    local t0

    # Step 5: untracked secret files
    t0=$(now)
    local secret_pattern='(^|/)(\.env(\..+)?|.*\.key|.*\.pem|id_rsa|id_ed25519|id_ecdsa|aws-credentials|\.netrc)$'
    # NUL-delimited so paths with spaces / special chars are matched (porcelain
    # quotes such paths and a whitespace split would miss them).
    local untracked="" entry path
    while IFS= read -r -d '' entry; do
        [ "${entry:0:2}" = "??" ] || continue
        path="${entry:3}"
        if printf '%s' "$path" | grep -qE "$secret_pattern"; then
            untracked="${untracked}${path}
"
        fi
    done < <(git status --porcelain -z 2>/dev/null)
    if [ -n "$untracked" ]; then
        record 5 fail $(( $(now) - t0 )); printf '%s' "$untracked" > "$work/5.detail"
    else
        record 5 pass $(( $(now) - t0 ))
    fi

    # Step 6: hardcoded secrets in the cumulative diff
    t0=$(now)
    local default_branch=""
    # Resolve the project bundle by globbing `*.plumage` in cwd (the project
    # root, whether claude runs inside Plumage or standalone). BundleResolver
    # guarantees exactly one per root. The `! -name '.*'` excludes the legacy
    # hidden `.plumage` dotfolder (find's `*` matches a leading dot, unlike
    # BundleResolver's extension check) so a rotting dotfolder never shadows
    # the real bundle. Empty glob → fall back to git refs below.
    local bundle
    bundle=$(find . -maxdepth 1 -type d -name '*.plumage' ! -name '.*' | head -1)
    if [ -n "$bundle" ] && [ -f "$bundle/config.json" ] && command -v jq >/dev/null 2>&1; then
        default_branch=$(jq -r '.git.defaultBranch // empty' "$bundle/config.json" 2>/dev/null || true)
    fi
    if [ -z "$default_branch" ]; then
        if git show-ref --verify --quiet refs/heads/main; then default_branch=main
        elif git show-ref --verify --quiet refs/heads/master; then default_branch=master; fi
    fi
    if [ -z "$default_branch" ]; then
        record 6 skip 0 "no default branch found (main/master)"
    else
        local diff_secrets
        # Same pattern set as block-secrets-in-content.sh — the diff scan and
        # the write hook must block the same list.
        diff_secrets=$(git diff "${default_branch}...HEAD" 2>/dev/null | grep -E \
            -e 'AKIA[0-9A-Z]{16}' -e 'ASIA[0-9A-Z]{16}' \
            -e 'gh[poasu]_[A-Za-z0-9]{30,}' \
            -e 'sk-(ant-|proj-|live-|admin-)?[A-Za-z0-9_-]{20,}' \
            -e 'sk_(live|test)_[A-Za-z0-9]{20,}' -e 'rk_(live|test)_[A-Za-z0-9]{20,}' \
            -e 'xox[baprs]-[A-Za-z0-9-]{10,}' -e 'AIza[0-9A-Za-z_-]{35}' \
            -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' || true)
        if [ -n "$diff_secrets" ]; then
            record 6 fail $(( $(now) - t0 )); printf '%s\n' "$diff_secrets" | head -10 > "$work/6.detail"
        else
            record 6 pass $(( $(now) - t0 ))
        fi
    fi

    # Step 7: .gitignore sanity (first commit only)
    t0=$(now)
    if [ $first_commit -eq 0 ]; then
        record 7 skip 0 "not first commit"
    elif [ ! -f .gitignore ]; then
        record 7 fail 0; echo ".gitignore is missing" > "$work/7.detail"
    else
        local missing=()
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
            record 7 pass 0
        else
            record 7 fail 0; printf 'missing: %s\n' "${missing[*]}" > "$work/7.detail"
        fi
    fi
}

# ---- Run the three tracks: B and C in the background, A in the foreground ----

gate_start=$(now)
track_b & b_pid=$!
track_c & c_pid=$!
track_a
wait "$b_pid"; b_rc=$?
wait "$c_pid"; c_rc=$?

# A track that died on a signal (segfault, OOM-kill) leaves its remaining steps
# unrecorded; the assembler below turns a missing status into a failure, so the
# non-zero rc here is informational. Surface it so the cause is visible.
[ "$b_rc" -ne 0 ] && echo "warning: lint/format track exited abnormally (rc=$b_rc)" >&2
[ "$c_rc" -ne 0 ] && echo "warning: secret/gitignore track exited abnormally (rc=$c_rc)" >&2

# ---- Assemble the numbered output in fixed order ----------------------------

names=(
    "Build (zero errors, zero warnings)"
    "Tests"
    "SwiftLint (zero violations)"
    "swift-format (lint mode)"
    "Untracked secrets check (git status)"
    "Hardcoded secrets check (git diff)"
    ".gitignore sanity"
)
total=7
failures=0

for n in 1 2 3 4 5 6 7; do
    # A missing status means the responsible track died before recording this
    # step (every code path otherwise calls `record`). Treat that as a failure,
    # never a silent skip — a crashed lint/secret track must not pass the gate.
    if [ -f "$work/$n.status" ]; then
        status=$(cat "$work/$n.status")
    else
        status=fail
        [ -s "$work/$n.detail" ] || printf 'check did not complete (track crashed before recording)' > "$work/$n.detail"
    fi
    secs=$(cat "$work/$n.secs" 2>/dev/null || echo 0)
    reason=$(cat "$work/$n.reason" 2>/dev/null || true)
    t=""
    [ $timing -eq 1 ] && t=$(printf ' (%ss)' "$secs")
    printf '[%d/%d] %s... ' "$n" "$total" "${names[$((n-1))]}"
    case "$status" in
        pass) printf 'PASS%s\n' "$t" ;;
        skip) printf 'SKIP%s%s\n' "${reason:+ ($reason)}" "$t" ;;
        fail)
            printf 'FAIL%s\n' "$t"
            failures=$((failures + 1))
            [ -s "$work/$n.detail" ] && sed 's/^/    /' "$work/$n.detail"
            ;;
    esac
done

# ---- Summary ----------------------------------------------------------------

echo
if [ $timing -eq 1 ]; then
    mode="default"; [ $full -eq 1 ] && mode="full"
    printf 'total: %ss (%s mode, warm cache)\n' "$(( $(now) - gate_start ))" "$mode"
fi
if [ $failures -eq 0 ]; then
    echo "GATE PASSED"
    exit 0
else
    echo "GATE FAILED ($failures failure$([ $failures -ne 1 ] && echo s))"
    exit 1
fi
