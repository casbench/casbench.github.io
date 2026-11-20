#!/usr/bin/env python3
"""Remove duplicated case rows from results files, keeping the last row of each index.

    python3 -I tools/dedupe_results.py results/<host>/*.tsv        # rewrite, report
    python3 -I tools/dedupe_results.py --check results/<host>/*.tsv  # exit 1 if a file has duplicates

A case index appears twice when the supervisor restarted a worker and both the
timeout record and the restarted worker's record of the same case were
appended (seen in F_integration_symbolics and F_integration_symj of the
2026-11-19 runs). The last row is the one the restarted worker wrote, after
the supervisor's record, so it is the one kept; rows are otherwise untouched
and keep their order.
"""
import sys


def dedupe(path, check):
    with open(path, encoding="utf-8", newline="") as f:
        lines = f.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    header, rows = lines[0], lines[1:]
    last = {}
    for i, l in enumerate(rows):
        f = l.split("\t")
        if len(f) > 3:
            last[f[2]] = i
    keep = [l for i, l in enumerate(rows) if len(l.split("\t")) <= 3 or last[l.split("\t")[2]] == i]
    dropped = len(rows) - len(keep)
    if dropped and not check:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write("\n".join([header] + keep) + "\n")
    return dropped


def main(argv):
    check = "--check" in argv
    paths = [a for a in argv if a != "--check"]
    total = 0
    for p in paths:
        d = dedupe(p, check)
        if d:
            total += d
            print(f"{p}: {d} duplicated row{'s' if d > 1 else ''} {'found' if check else 'removed'}")
    return 1 if (check and total) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
