#!/usr/bin/env python3
# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

"""Verifies that documentation code excerpts are real code.

A fenced block whose first line is `# From: <path>` (or `// From: <path>` for TypeScript) is an
excerpt of a file in this repository. Every other line of the block must appear, in order and
contiguously, in that file. Indentation and blank lines are ignored, so an excerpt may be dedented
out of a module. Blocks without the marker are illustrative and are not checked here.

Run from anywhere. Exits non-zero and names each excerpt that has drifted from its source.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "Documentation"
FENCE = re.compile(r"```[^\n]*\n(.*?)\n```", re.DOTALL)
MARKER = re.compile(r"^(?:#|//) From: (\S+)\s*$")


def significant(lines):
    return [line.strip() for line in lines if line.strip()]


def contains(haystack, needle):
    n = len(needle)
    return n == 0 or any(haystack[i : i + n] == needle for i in range(len(haystack) - n + 1))


def main():
    failures = []
    checked = 0

    for page in sorted(DOCS.rglob("*.md")):
        text = page.read_text()
        for match in FENCE.finditer(text):
            lines = match.group(1).split("\n")
            marker = MARKER.match(lines[0])
            if not marker:
                continue

            checked += 1
            source = ROOT / marker.group(1)
            where = f"{page.relative_to(ROOT)}: {marker.group(1)}"

            if not source.is_file():
                failures.append(f"{where}: the source file does not exist")
                continue

            if not contains(significant(source.read_text().split("\n")), significant(lines[1:])):
                failures.append(f"{where}: the excerpt no longer matches its source")

    for failure in failures:
        print(failure, file=sys.stderr)

    print(f"Checked {checked} excerpts, {len(failures)} drifted.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
