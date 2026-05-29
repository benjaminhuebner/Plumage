#!/usr/bin/env python3
"""spec-task-tick.py — mark a task as done in an issue spec.

Used by the /plumage-implement skill at the end of a task. Doing this with the Edit
tool is fragile: a `[ ]` inside a code block can be misidentified as a task,
and the `updated:` field is YAML-frontmatter that needs careful handling. This
script does both correctly: parse frontmatter, count tasks under the `## Tasks`
header only, skip fenced code blocks, tick the Nth unchecked one, write
`updated:` to now.

Usage:
    spec-task-tick.py <spec-path> --task N

Where N is 1-based, counting only unchecked tasks at the time of invocation
that are *outside* fenced code blocks. So "--task 1" always means "the next
unchecked task in the live task list".

Exit codes:
    0  success
    1  usage error or invalid spec
    2  no unchecked task at that index (e.g., task N is already done, or the
       task list is shorter than expected)
"""

from __future__ import annotations

import argparse
import datetime
import re
import sys
from pathlib import Path


FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
TASKS_HEADER_RE = re.compile(r"^## Tasks\s*$", re.MULTILINE)
NEXT_H2_RE = re.compile(r"^## ", re.MULTILINE)
TASK_LINE_RE = re.compile(r"^(- \[) \](.*)$")
# A fence opener/closer per CommonMark: a line that starts with three or more
# backticks or tildes, optionally followed by an info string. The closer must
# use the same character as the opener — that's why fence_char is tracked.
FENCE_RE = re.compile(r"^(`{3,}|~{3,})")
UPDATED_RE = re.compile(r"^updated:.*$", re.MULTILINE)


def parse_frontmatter(content: str) -> tuple[str, str]:
    """Return (frontmatter_text, body_text). Raise if no frontmatter."""
    m = FRONTMATTER_RE.match(content)
    if not m:
        raise ValueError("spec has no YAML frontmatter")
    fm = m.group(1)
    body = content[m.end():]
    return fm, body


def find_tasks_block(body: str) -> tuple[int, int]:
    """Return (start, end) character indices of the `## Tasks` section body
    (after the header line, up to the next ## or EOF). Raises if not found."""
    header = TASKS_HEADER_RE.search(body)
    if not header:
        raise ValueError("spec has no `## Tasks` section")
    block_start = body.find("\n", header.end()) + 1
    next_h2 = NEXT_H2_RE.search(body, block_start)
    block_end = next_h2.start() if next_h2 else len(body)
    return block_start, block_end


def tick_nth_unchecked(tasks_block: str, n: int) -> tuple[str, bool]:
    """Tick the Nth unchecked task (1-based), skipping fenced code blocks.

    A line like `- [ ]` inside a ``` or ~~~ fence is treated as content
    (e.g., a code example), not a task.
    """
    lines = tasks_block.split("\n")
    unchecked_count = 0
    inside_fence = False
    fence_char: str | None = None  # which character opened the fence; only its match closes it
    for i, line in enumerate(lines):
        fm = FENCE_RE.match(line)
        if fm:
            marker = fm.group(1)[0]  # '`' or '~'
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
            unchecked_count += 1
            if unchecked_count == n:
                lines[i] = f"{m.group(1)}x]{m.group(2)}"
                return "\n".join(lines), True
    return tasks_block, False


def update_frontmatter_timestamp(fm: str) -> str:
    """Update or append `updated:` field with current UTC time."""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    new_line = f"updated: {now}"
    if UPDATED_RE.search(fm):
        return UPDATED_RE.sub(new_line, fm, count=1)
    return fm.rstrip() + "\n" + new_line + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("spec", help="Path to the spec.md")
    parser.add_argument("--task", type=int, required=True,
                        help="Which unchecked task to tick (1-based)")
    args = parser.parse_args()

    spec_path = Path(args.spec)
    if not spec_path.is_file():
        print(f"error: spec not found at {spec_path}", file=sys.stderr)
        return 1

    if args.task < 1:
        print(f"error: --task must be >= 1, got {args.task}", file=sys.stderr)
        return 1

    content = spec_path.read_text(encoding="utf-8")

    try:
        fm, body = parse_frontmatter(content)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    try:
        ts, te = find_tasks_block(body)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    tasks_block = body[ts:te]
    new_tasks, ticked = tick_nth_unchecked(tasks_block, args.task)
    if not ticked:
        print(f"error: no unchecked task #{args.task} in this spec "
              f"(it may already be done, or the list is shorter)",
              file=sys.stderr)
        return 2

    new_body = body[:ts] + new_tasks + body[te:]
    new_fm = update_frontmatter_timestamp(fm)
    new_content = f"---\n{new_fm.rstrip()}\n---\n{new_body}"

    # Atomic write — tmp file + rename. Avoids half-written specs on crash.
    tmp_path = spec_path.with_suffix(spec_path.suffix + ".tmp")
    tmp_path.write_text(new_content, encoding="utf-8")
    tmp_path.replace(spec_path)

    return 0


if __name__ == "__main__":
    sys.exit(main())
