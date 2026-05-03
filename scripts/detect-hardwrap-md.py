#!/usr/bin/env python3
"""detect-hardwrap-md — classify markdown files as hard-wrapped or soft-wrapped.

Companion to scripts/reflow-md.py. Use this to find candidate files for a
reflow pass; reflow is then applied per-file with reflow-md.py.

How it classifies:
  Examines prose lines (non-blank, non-code-fence, non-heading, non-table,
  non-list-item, non-blockquote, non-HR, non-frontmatter-delim, not-indented).
  For each prose line, captures (length, ends-with-sentence-terminal,
  next-line-starts-lowercase). Files with median prose length < 90 chars
  AND >5% "wrap-evidence" (short line followed by a lowercase continuation)
  are classified as hard-wrapped. Files with median > 200 are soft-wrapped.
  Otherwise: ambiguous.

Known false positives:
  - Files dominated by short bullet items + atomic-paragraph prose
    (governance/shim-policy.md, architecture/02_PLAN.md). Median is small
    not because paragraphs are wrapped but because content is naturally
    short. Reflow on these is a no-op (correctly), so a false-positive
    classification has zero risk — the worst case is a wasted reflow run.
  - Auto-generated catalogs (docs/index.md). Skip these manually.

Usage:
  scripts/detect-hardwrap-md.py <files...>

  # Typical sweep:
  find docs -name '*.md' -not -path 'docs/history/*' \\
    -not -path 'docs/archive/*' -not -path 'docs/badges/*' \\
    | xargs scripts/detect-hardwrap-md.py

Output groups:
  HARD-WRAPPED — needs reflow (run scripts/reflow-md.py on each).
  SOFT-WRAPPED — already in target form.
  AMBIGUOUS    — manual review (often short structured docs; usually fine).
  SKIPPED      — too tiny to classify (< 5 prose lines).

History: introduced 2026-05-02 during M-CONTRACT-02 wrap-time docs cleanup.
"""

import re
import sys
from pathlib import Path
from statistics import median


SKIP_PREFIXES = ("    ",)
HORIZONTAL_RULE = re.compile(r'^[\s]*[-*_]{3,}\s*$')
LIST_ITEM = re.compile(r'^(\s*)([-*+]|\d+\.)\s+')


def classify(path):
    text = Path(path).read_text()
    lines = text.split('\n')

    in_code = False
    prose_lines = []  # (length, ends_with_terminal, next_starts_lower)

    for i, line in enumerate(lines):
        stripped = line.lstrip()

        if stripped.startswith('```') or stripped.startswith('~~~'):
            in_code = not in_code
            continue
        if in_code:
            continue
        if not stripped:
            continue
        if stripped.startswith('#'):
            continue
        if stripped.startswith('|'):
            continue
        if stripped.startswith('>'):
            continue
        if HORIZONTAL_RULE.match(line):
            continue
        if LIST_ITEM.match(line):
            continue
        if stripped.startswith('---'):  # frontmatter delim
            continue
        if line.startswith(SKIP_PREFIXES):
            continue

        ends_terminal = stripped.rstrip().endswith(('.', '!', '?', ':', ')', ']', '"', '`'))
        next_idx = i + 1
        next_starts_lower = False
        if next_idx < len(lines):
            nxt = lines[next_idx].lstrip()
            if nxt and nxt[0].islower():
                next_starts_lower = True

        prose_lines.append((len(line.rstrip()), ends_terminal, next_starts_lower))

    if len(prose_lines) < 5:
        return ('skip-tiny', 0, 0)

    lengths = [p[0] for p in prose_lines]
    med_len = median(lengths)

    # A line is "wrap-evidence" if it's short AND the next line is a lowercase
    # continuation. That's the signature of hard-wrapped prose.
    wrap_evidence = sum(1 for p in prose_lines if p[0] < 80 and p[2])
    wrap_ratio = wrap_evidence / len(prose_lines)

    if med_len < 90 and wrap_ratio > 0.05:
        return ('hard-wrapped', round(med_len), round(wrap_ratio * 100))
    if med_len > 200:
        return ('soft-wrapped', round(med_len), round(wrap_ratio * 100))
    return ('ambiguous', round(med_len), round(wrap_ratio * 100))


def main(paths):
    hard = []
    soft = []
    ambig = []
    skipped = []
    for p in sorted(paths):
        verdict, med, wrap_pct = classify(p)
        if verdict == 'hard-wrapped':
            hard.append((p, med, wrap_pct))
        elif verdict == 'soft-wrapped':
            soft.append((p, med, wrap_pct))
        elif verdict == 'ambiguous':
            ambig.append((p, med, wrap_pct))
        else:
            skipped.append(p)

    print(f"=== HARD-WRAPPED ({len(hard)}) — needs reflow ===")
    for p, med, wp in hard:
        print(f"  median={med:3d}  wrap={wp:3d}%  {p}")
    print(f"\n=== SOFT-WRAPPED ({len(soft)}) — already in target form ===")
    for p, med, wp in soft:
        print(f"  median={med:4d}  wrap={wp:3d}%  {p}")
    print(f"\n=== AMBIGUOUS ({len(ambig)}) — manual review ===")
    for p, med, wp in ambig:
        print(f"  median={med:3d}  wrap={wp:3d}%  {p}")
    print(f"\n=== SKIPPED (too tiny) ({len(skipped)}) ===")
    for p in skipped:
        print(f"  {p}")


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1:])
