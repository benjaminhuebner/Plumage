#!/usr/bin/env python3
"""roadmap.py — print a project-state view derived from all issue specs.

Scans .claude/issues/*/spec.md, reads each frontmatter, counts task progress,
and prints a grouped markdown view (or JSON with --json). Nothing is written
to disk unless --write is passed. The spec.md frontmatters remain the only
source of truth — this script is a read-only view.

Usage:
    roadmap.py                       # markdown to stdout
    roadmap.py --json                # JSON to stdout
    roadmap.py --all                 # include all done issues (default: last 10)
    roadmap.py --no-archive          # skip .claude/issues/archive/
    roadmap.py --status in-progress  # filter to one status
    roadmap.py --write ROADMAP.md    # write to file instead of stdout

Exit codes:
    0  success
    1  no issues found, or other operational error
    2  invalid argument
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

ISSUES_DIR_DEFAULT = ".claude/issues"
ARCHIVE_SUBDIR = "archive"

# Same fence handling as spec-task-tick.py — match what's there.
FENCE_RE = re.compile(r"^(`{3,}|~{3,})")
TASK_LINE_RE = re.compile(r"^- \[([ xX])\]")
TASKS_HEADER_RE = re.compile(r"^## Tasks\s*$", re.MULTILINE)
NEXT_H2_RE = re.compile(r"^## ", re.MULTILINE)
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)

STATUS_ORDER = [
    "in-progress",
    "waiting-for-review",
    "approved",
    "draft",
    "done",
]
STATUS_LABEL = {
    "in-progress": "In Progress",
    "waiting-for-review": "Waiting for Review",
    "approved": "Approved",
    "draft": "Draft",
    "done": "Done",
}


def parse_frontmatter(text: str) -> dict[str, str]:
    """Return a dict of top-level key:value pairs from YAML-like frontmatter.

    Simple parser — handles `key: value` lines only. Lists (`labels: [a, b]`)
    are returned as the raw bracketed string; the caller can split if needed.
    Sufficient for Plumage's flat frontmatter schema.
    """
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        line = line.rstrip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        # Strip surrounding quotes if present.
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
            val = val[1:-1]
        out[key] = val
    return out


def count_tasks(text: str) -> tuple[int, int]:
    """Return (done, total) for the spec's `## Tasks` section, skipping
    `- [ ]` and `- [x]` inside fenced code blocks and other sections.
    """
    fm_match = FRONTMATTER_RE.match(text)
    body = text[fm_match.end():] if fm_match else text

    header = TASKS_HEADER_RE.search(body)
    if not header:
        return 0, 0
    block_start = body.find("\n", header.end()) + 1
    next_h2 = NEXT_H2_RE.search(body, block_start)
    block_end = next_h2.start() if next_h2 else len(body)
    tasks_block = body[block_start:block_end]

    inside_fence = False
    fence_char: str | None = None
    done = total = 0
    for line in tasks_block.split("\n"):
        fm = FENCE_RE.match(line)
        if fm:
            marker = fm.group(1)[0]
            if not inside_fence:
                inside_fence = True
                fence_char = marker
            elif marker == fence_char:
                inside_fence = False
                fence_char = None
            continue
        if inside_fence:
            continue
        m = TASK_LINE_RE.match(line)
        if m:
            total += 1
            if m.group(1) in ("x", "X"):
                done += 1
    return done, total


def collect_issues(issues_dir: Path, include_archive: bool) -> list[dict]:
    """Walk the issues directory, parse each spec.md, return a list of dicts."""
    issues: list[dict] = []
    if not issues_dir.exists():
        return issues

    # Active issues: direct children of issues_dir (skip the archive subdir).
    for entry in sorted(issues_dir.iterdir()):
        if not entry.is_dir():
            continue
        if entry.name == ARCHIVE_SUBDIR:
            continue
        spec = entry / "spec.md"
        if not spec.is_file():
            continue
        issues.append(_load_spec(spec, archived=False))

    # Archived issues: under issues_dir/archive/.
    archive_dir = issues_dir / ARCHIVE_SUBDIR
    if include_archive and archive_dir.is_dir():
        for entry in sorted(archive_dir.iterdir()):
            if not entry.is_dir():
                continue
            spec = entry / "spec.md"
            if not spec.is_file():
                continue
            issues.append(_load_spec(spec, archived=True))

    return issues


def _load_spec(spec_path: Path, archived: bool) -> dict:
    """Read one spec, return a normalized dict."""
    text = spec_path.read_text(encoding="utf-8", errors="replace")
    fm = parse_frontmatter(text)
    done, total = count_tasks(text)
    return {
        "id": _int_or_none(fm.get("id", "")),
        "title": fm.get("title", ""),
        "type": fm.get("type", ""),
        "status": fm.get("status", ""),
        "created": fm.get("created", ""),
        "updated": fm.get("updated", ""),
        "slug": spec_path.parent.name,
        "tasks_done": done,
        "tasks_total": total,
        "archived": archived,
    }


def _int_or_none(s: str):
    try:
        return int(s)
    except (TypeError, ValueError):
        return None


def group_issues(issues: list[dict], status_filter: str | None) -> dict[str, list[dict]]:
    """Group issues by status. Done bucket includes archived issues."""
    groups: dict[str, list[dict]] = {s: [] for s in STATUS_ORDER}
    other: list[dict] = []
    for issue in issues:
        status = issue["status"]
        if status_filter and status != status_filter:
            continue
        if status in groups:
            groups[status].append(issue)
        else:
            other.append(issue)

    # In-progress and waiting: most recently updated first.
    for key in ("in-progress", "waiting-for-review", "done"):
        groups[key].sort(key=lambda i: i["updated"] or i["created"] or "", reverse=True)
    # Approved and draft: by id ascending (oldest first to pick up).
    for key in ("approved", "draft"):
        groups[key].sort(key=lambda i: i["id"] if i["id"] is not None else 10**9)

    if other:
        groups["_other"] = other
    return groups


def render_markdown(groups: dict[str, list[dict]], done_limit: int | None) -> str:
    """Render the grouped issues as a markdown report."""
    lines: list[str] = []
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines.append(f"# Project state — generated {now}\n")

    nothing_shown = True
    for status in STATUS_ORDER:
        items = groups.get(status, [])
        if not items:
            continue

        shown = items
        suffix = ""
        if status == "done" and done_limit is not None and len(items) > done_limit:
            shown = items[:done_limit]
            suffix = f" (showing latest {done_limit} of {len(items)})"

        nothing_shown = False
        lines.append(f"## {STATUS_LABEL[status]} ({len(items)}){suffix}")
        for issue in shown:
            lines.append(_format_issue_line(issue))
        lines.append("")

    other = groups.get("_other", [])
    if other:
        nothing_shown = False
        lines.append(f"## Other / unknown status ({len(other)})")
        for issue in other:
            lines.append(_format_issue_line(issue))
        lines.append("")

    if nothing_shown:
        lines.append("_No issues found._\n")

    return "\n".join(lines).rstrip() + "\n"


def _format_issue_line(issue: dict) -> str:
    pad = 5  # Default; could read issueIdPadding from <bundle>/config.json but cheap default is fine here.
    id_str = f"#{issue['id']:0{pad}d}" if isinstance(issue["id"], int) else "#?????"
    title = issue["title"] or issue["slug"]
    parts = [f"- {id_str} {title}"]

    if issue["tasks_total"] > 0:
        parts.append(f"— {issue['tasks_done']}/{issue['tasks_total']} tasks")

    if issue["type"] and issue["type"] != "feature":
        parts.append(f"[{issue['type']}]")

    if issue["status"] == "in-progress" and issue["updated"]:
        parts.append(f"updated {issue['updated'][:10]}")
    elif issue["status"] == "done" and issue["updated"]:
        parts.append(f"done {issue['updated'][:10]}")
    elif issue["status"] == "draft" and issue["created"]:
        parts.append(f"created {issue['created'][:10]}")

    if issue["archived"]:
        parts.append("(archived)")

    return " ".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", action="store_true",
                        help="output JSON instead of markdown")
    parser.add_argument("--all", action="store_true",
                        help="include all done issues (default: latest 10)")
    parser.add_argument("--no-archive", action="store_true",
                        help="skip .claude/issues/archive/")
    parser.add_argument("--status", choices=STATUS_ORDER,
                        help="show only issues with this status")
    parser.add_argument("--write", metavar="PATH",
                        help="write output to PATH instead of stdout")
    parser.add_argument("--issues-dir", default=ISSUES_DIR_DEFAULT,
                        help=f"issues directory (default: {ISSUES_DIR_DEFAULT})")
    args = parser.parse_args()

    issues_dir = Path(args.issues_dir)
    if not issues_dir.exists():
        print(f"error: issues directory not found at {issues_dir}", file=sys.stderr)
        return 1

    issues = collect_issues(issues_dir, include_archive=not args.no_archive)
    groups = group_issues(issues, status_filter=args.status)
    done_limit = None if args.all else 10

    if args.json:
        # Strip the synthetic '_other' bucket name for JSON output.
        out = {
            "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
            "by_status": {k: v for k, v in groups.items() if not k.startswith("_")},
            "other": groups.get("_other", []),
        }
        output = json.dumps(out, indent=2)
    else:
        output = render_markdown(groups, done_limit)

    if args.write:
        Path(args.write).write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output if output.endswith("\n") else output + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
