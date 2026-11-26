#!/usr/bin/env python3
"""Publish a host under a neutral name, without the machine's own name or its user's paths.

    python3 -I tools/anonymize_host.py results <old-host> <new-host>

- renames results/<old-host>/ to results/<new-host>/ and replaces the old name, in any case, in its files
  (run ids, run directories, machine.txt) and in results/history.tsv;
- in that host's SOURCES.tsv, keeps the checksum of each file as the harness wrote it (sha256_as_written)
  and records the checksum of the published file (sha256), so the review archive still matches;
- removes from every host's environment.txt what versioninfo(verbose=true) adds about the user and the
  session (environment variables other than JULIA_* and TERM, uptime, load, per-CPU counters).

This is a renaming, not an edit of the measurements: no status, time or answer changes. Run
make_tables.jl afterwards, since the tables and the history name the host.
"""
import hashlib
import pathlib
import re
import sys

ENV_VAR = re.compile(r"^  ([A-Za-z_][A-Za-z0-9_]*) = ")
CPU_COUNTERS = re.compile(r"^\s+(speed\s+user\s+nice|#\d)")
SESSION = re.compile(r"^\s+(Uptime|Load Avg):")
HOME = re.compile(r"/home/[^/\s:]+")
KEPT_VARS = re.compile(r"^(JULIA_|TERM$)")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scrub_environment(text):
    """Drop the user's environment and the session counters from an environment.txt; idempotent."""
    out = []
    for line in text.splitlines(keepends=True):
        m = ENV_VAR.match(line)
        if m and not KEPT_VARS.match(m.group(1)):
            continue
        if CPU_COUNTERS.match(line) or SESSION.match(line):
            continue
        out.append(HOME.sub("~", line))
    return "".join(out)


def _sources(path):
    """Rewrite SOURCES.tsv: the sha256 of the published file, the run's own checksum kept beside it."""
    lines = path.read_text(encoding="utf-8").splitlines()
    out, header = [], None
    for line in lines:
        if line.startswith("#"):
            out.append(line)
            continue
        cols = line.split("\t")
        if header is None:
            header = cols
            if "sha256_as_written" in header:
                return
            out.append("# Published under a neutral host name (tools/anonymize_host.py): sha256 is the checksum "
                       "of the published file, sha256_as_written that of the file the run wrote.")
            out.append("\t".join(header + ["sha256_as_written"]))
            continue
        row = dict(zip(header, cols))
        f = path.parent / row["file"]
        old = row.get("sha256", "")
        row["sha256"] = sha256(f) if f.exists() else old
        out.append("\t".join([row.get(k, "") for k in header] + [old]))
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def rename_host(results, old, new):
    results = pathlib.Path(results)
    src, dst = results / old, results / new
    if not src.is_dir():
        sys.exit(f"no host directory {src}")
    if dst.exists():
        sys.exit(f"refusing to replace {dst}")
    src.rename(dst)
    name = re.compile(re.escape(old), re.IGNORECASE)
    for p in sorted([*dst.iterdir(), results / "history.tsv"]):
        if p.is_file():
            text = p.read_text(encoding="utf-8")
            new_text = name.sub(new, text)
            if new_text != text:
                p.write_text(new_text, encoding="utf-8")
    if (dst / "SOURCES.tsv").exists():
        _sources(dst / "SOURCES.tsv")


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    results, old, new = argv
    rename_host(results, old, new)
    for env in sorted(pathlib.Path(results).glob("*/environment.txt")):
        text = env.read_text(encoding="utf-8")
        scrubbed = scrub_environment(text)
        if scrubbed != text:
            env.write_text(scrubbed, encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1:])
