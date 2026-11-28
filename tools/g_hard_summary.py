#!/usr/bin/env python3
"""The summary of a hard-tier results file of bench G, for publication in results/<host>/.

    python3 -I tools/g_hard_summary.py G_groebner_hard_<system>.tsv... --out DIR

A hard-tier file holds the full reduced Gröbner bases, up to 104 MB, over GitHub's file and Pages limits: the full file is
published as an asset of a GitHub release, with its checksum, and the repository holds this summary,
G_groebner_hard_<system>_summary.tsv: the same records (status, times, the note with the basis digest, size and
check time, load, run id), with the answer (`result`) and the input sent (`input`, `verify_input`) left empty. Nothing
else is changed; SOURCES.tsv names the full file, its checksum and the release.
"""
import argparse
import csv
import hashlib
import pathlib
import sys

csv.field_size_limit(1 << 30)
EMPTIED = ("result", "input", "verify_input")


def summary_text(text):
    lines = text.splitlines(keepends=True)
    header = lines[0].rstrip("\n").split("\t")
    idx = [header.index(c) for c in EMPTIED if c in header]
    out = [lines[0]]
    for line in lines[1:]:
        end = "\n" if line.endswith("\n") else ""
        cols = line.rstrip("\n").split("\t")
        for i in idx:
            if i < len(cols):
                cols[i] = ""
        out.append("\t".join(cols) + end)
    return "".join(out)


def summary_name(name):
    if not (name.startswith("G_groebner_hard_") and name.endswith(".tsv")):
        sys.exit(f"not a hard-tier results file: {name}")
    return name[:-4] + "_summary.tsv"


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    out = pathlib.Path(a.out)
    for f in map(pathlib.Path, a.files):
        raw = f.read_bytes()
        dst = out / summary_name(f.name)
        dst.write_text(summary_text(raw.decode("utf-8")), encoding="utf-8")
        print(f"{dst.name}\t{f.name}\t{hashlib.sha256(raw).hexdigest()}")


if __name__ == "__main__":
    main(sys.argv[1:])
