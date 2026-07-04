#!/usr/bin/env python3
# spec-set-status.py — set the `status:` frontmatter field of an issue spec.
#
# Used by start-run.sh (approved/draft -> in-progress) and finish-run.sh
# (in-progress -> waiting-for-review). Doing this with the Edit tool is fragile
# (the word can appear in the body) and every Edit costs an agent round-trip.
# This script edits only the frontmatter line and bumps `updated:` to now,
# with the same atomic tmp+rename write as spec-task-tick.py.
#
# Usage:
#     spec-set-status.py <spec-path> <status>
#
# Exit codes:
#     0  success
#     1  usage error or invalid spec

from __future__ import annotations

import datetime
import re
import sys
from pathlib import Path

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
STATUS_RE = re.compile(r"^status:.*$", re.MULTILINE)
UPDATED_RE = re.compile(r"^updated:.*$", re.MULTILINE)
VALID_STATUS_RE = re.compile(r"^[a-z][a-z-]*$")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: spec-set-status.py <spec-path> <status>", file=sys.stderr)
        return 1

    spec_path = Path(sys.argv[1])
    status = sys.argv[2]

    if not VALID_STATUS_RE.match(status):
        print(f"error: invalid status token: {status!r}", file=sys.stderr)
        return 1
    if not spec_path.is_file():
        print(f"error: spec not found at {spec_path}", file=sys.stderr)
        return 1

    content = spec_path.read_text(encoding="utf-8")
    m = FRONTMATTER_RE.match(content)
    if not m:
        print("error: spec has no YAML frontmatter", file=sys.stderr)
        return 1

    fm = m.group(1)
    if not STATUS_RE.search(fm):
        print("error: frontmatter has no `status:` field", file=sys.stderr)
        return 1

    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    fm = STATUS_RE.sub(f"status: {status}", fm, count=1)
    if UPDATED_RE.search(fm):
        fm = UPDATED_RE.sub(f"updated: {now}", fm, count=1)
    else:
        fm = fm.rstrip() + f"\nupdated: {now}"

    new_content = f"---\n{fm.rstrip()}\n---\n" + content[m.end():]
    tmp_path = spec_path.with_suffix(spec_path.suffix + ".tmp")
    tmp_path.write_text(new_content, encoding="utf-8")
    tmp_path.replace(spec_path)
    print(f"status: {status} ({spec_path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
