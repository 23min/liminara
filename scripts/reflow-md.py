#!/usr/bin/env python3
"""reflow-md — collapse hard-wrapped markdown prose into one paragraph per line.

Liminara's docs convention (see .ai-repo/rules/liminara.md and the per-area
notes in docs/architecture/02_PLAN.md / docs/governance/) is one paragraph
per line for narrative prose under docs/. Hard-wrapped paragraphs (each line
~65 chars, common in older ADRs and inherited content) are normalized into
single-line paragraphs by this tool. Renderers handle wrapping at display
time; the source-level convention keeps diffs clean (changes show as
single-line edits, not whole-paragraph re-wraps).

What is preserved verbatim:
  - YAML frontmatter (`---` ... `---` at file head).
  - Fenced code blocks (``` and ~~~).
  - ATX headings (lines starting with `#`).
  - Tables (lines starting with `|`).
  - Horizontal rules (`---`, `***`, `___`).
  - Blank lines (paragraph separators).
  - Indented code blocks are NOT specially detected (use fenced blocks).

What is collapsed:
  - Plain prose paragraphs: consecutive non-block-break lines join with spaces.
  - List items + their continuation lines: indented continuation joins back.
  - Blockquotes (consecutive `>`-prefixed lines join with spaces).

Usage:
  scripts/reflow-md.py <path-to-markdown-file>

Idempotent — running it twice on the same file produces the same result.
Round-trip safe with the docs/badges/ regenerator and the wf-doc-lint index.

Companion tool: scripts/detect-hardwrap-md.py classifies which files would
benefit from a reflow pass.

History: introduced 2026-05-02 during M-CONTRACT-02 wrap-time docs cleanup.
The earlier ad-hoc /tmp/ version had a YAML-frontmatter bug that collapsed
multi-key blocks onto one line; this version's pass-through-frontmatter
discipline catches that case explicitly.
"""

import re
import sys


HORIZONTAL_RULE = re.compile(r'^[\s]*[-*_]{3,}\s*$')
LIST_ITEM = re.compile(r'^(\s*)([-*+]|\d+\.)\s+')


def is_block_break(line):
    """Return True if the line starts a structural element that ends a paragraph."""
    s = line.lstrip()
    if not s:
        return True
    if s.startswith('#'):
        return True
    if s.startswith('```') or s.startswith('~~~'):
        return True
    if s.startswith('|'):
        return True
    if HORIZONTAL_RULE.match(line):
        return True
    if s.startswith('>'):
        return True
    if LIST_ITEM.match(line):
        return True
    return False


def reflow(path):
    with open(path, 'r') as f:
        src = f.read()
    lines = src.split('\n')

    out = []
    i = 0
    n = len(lines)
    in_code = False

    # Pass-through YAML frontmatter (lines from "---" at line 0 to next "---")
    # verbatim — never reflow YAML key:value structure. The first version of
    # this tool elided the frontmatter check and collapsed multi-key blocks
    # onto one line, breaking YAML parsing; this is the load-bearing fix.
    if n > 0 and lines[0].strip() == '---':
        out.append(lines[0])
        i = 1
        while i < n and lines[i].strip() != '---':
            out.append(lines[i])
            i += 1
        if i < n:
            out.append(lines[i])
            i += 1

    while i < n:
        line = lines[i]
        stripped = line.lstrip()

        # Fenced code: toggle and pass-through every line until the matching fence.
        if stripped.startswith('```') or stripped.startswith('~~~'):
            out.append(line)
            in_code = not in_code
            i += 1
            continue

        if in_code:
            out.append(line)
            i += 1
            continue

        # Blank line.
        if not stripped:
            out.append(line)
            i += 1
            continue

        # ATX heading - single line.
        if stripped.startswith('#'):
            out.append(line)
            i += 1
            continue

        # Horizontal rule.
        if HORIZONTAL_RULE.match(line):
            out.append(line)
            i += 1
            continue

        # Table row.
        if stripped.startswith('|'):
            out.append(line)
            i += 1
            continue

        # Blockquote: collapse all consecutive `>`-prefixed lines.
        if stripped.startswith('>'):
            collapsed = line.rstrip()
            j = i + 1
            while j < n:
                nxt = lines[j]
                nxt_s = nxt.lstrip()
                if not nxt_s.startswith('>'):
                    break
                collapsed += ' ' + nxt_s[1:].lstrip().rstrip()
                j += 1
            out.append(collapsed)
            i = j
            continue

        # List item: collapse the item + its continuation lines.
        m = LIST_ITEM.match(line)
        if m:
            collapsed = line.rstrip()
            j = i + 1
            while j < n:
                nxt = lines[j]
                if not nxt.strip():
                    break
                if is_block_break(nxt):
                    break
                # Continuation: any non-blank non-block-break following a list item.
                collapsed += ' ' + nxt.strip()
                j += 1
            out.append(collapsed)
            i = j
            continue

        # Plain prose paragraph.
        collapsed = line.rstrip()
        j = i + 1
        while j < n:
            nxt = lines[j]
            if not nxt.strip():
                break
            if is_block_break(nxt):
                break
            collapsed += ' ' + nxt.strip()
            j += 1
        out.append(collapsed)
        i = j

    with open(path, 'w') as f:
        f.write('\n'.join(out))


def usage():
    print(__doc__, file=sys.stderr)
    sys.exit(2)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        usage()
    if sys.argv[1] in ('-h', '--help'):
        usage()
    reflow(sys.argv[1])
