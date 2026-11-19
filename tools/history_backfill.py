#!/usr/bin/env python3
"""Backfill results/history.tsv from the git history of the results files.

    python3 -I tools/history_backfill.py

For every commit that changed results/ (oldest first) and every results file
whose content changed in that commit, one row is added, dated like
make_tables_history.jl dates a run: by the last block of results/machine.txt
(at that commit) that names the bench and the system; the commit hash is the
source. Rows already present (same date, bench, system) are kept.
"""
import csv
import io
import pathlib
import statistics
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
HISTORY = ROOT / "results" / "history.tsv"
HEADER = ["date", "bench", "system", "n", "verified", "wrong", "unverified", "unsolved", "unavailable", "error",
          "timeout", "t_warm_sum", "t_warm_median", "versions", "source"]
STATUSES = ("verified", "wrong", "unverified", "unsolved", "unavailable", "error", "timeout")
FIXED = {"host", "kernel", "cpu", "memory_GiB", "julia", "julia_threads", "bench", "system", "giac_version"}


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def run_dates(machine_text):
    """(bench, system label) -> (date, versions) from the last block naming the pair."""
    out, date, kv = {}, "", {}

    def flush():
        if "bench" in kv:
            vers = "; ".join(f"{k} {v}" for k, v in kv.items() if k not in FIXED)
            out[(kv["bench"], kv.get("system", ""))] = (date, vers)   # bench A writes no system key

    for line in machine_text.splitlines():
        if line.startswith("# "):
            flush(); date = line[2:].strip(); kv = {}
        elif "\t" in line:
            k, v = line.split("\t", 1); kv[k] = v
    flush()
    return out


def summarize(text):
    rows = [r for r in csv.DictReader(io.StringIO(text), delimiter="\t", quoting=csv.QUOTE_NONE) if r.get("case") != "_load"]
    label = rows[0]["system"] if rows else ""
    counts = {s: sum(r["status"] == s for r in rows) for s in STATUSES}
    tw = []
    for r in rows:
        if r["status"] == "verified":
            try:
                v = float(r["t_warm_s"])
                if v == v:
                    tw.append(v)
            except ValueError:
                pass
    return label, len(rows), counts, sum(tw), (statistics.median(tw) if tw else float("nan"))


def main():
    existing = []
    if HISTORY.exists():
        existing = list(csv.DictReader(open(HISTORY, newline="", encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE))
    seen = {(r["date"], r["bench"], r["system"]) for r in existing}
    commits = git("log", "--reverse", "--format=%H", "--", "results").split()
    last_blob = {}
    added = []
    for h in commits:
        tree = {}
        for line in git("ls-tree", h, "results/").splitlines():
            meta, path = line.split("\t", 1)
            tree[pathlib.Path(path).name] = meta.split()[2]
        if "machine.txt" not in tree:
            continue
        dates = run_dates(git("show", f"{h}:results/machine.txt"))
        for name, blob in sorted(tree.items()):
            if not name.endswith(".tsv") or name == "history.tsv" or last_blob.get(name) == blob:
                continue
            last_blob[name] = blob
            parts = name[:-4].split("_", 2)
            if len(parts) < 3:
                continue
            bench, system = parts[0] + "_" + parts[1], parts[2]
            label, n, counts, tsum, tmed = summarize(git("show", f"{h}:results/{name}"))
            d = dates.get((bench, label)) or dates.get((bench, system)) or dates.get((bench, ""))
            if d is None:
                continue
            date, vers = d
            key = (date, bench, system)
            if key in seen:
                continue
            added.append({"date": date, "bench": bench, "system": system, "n": n, **counts,
                          "t_warm_sum": f"{tsum:.6g}", "t_warm_median": f"{tmed:.6g}", "versions": vers, "source": h[:12]})
            seen.add(key)
    rows = existing + added
    rows.sort(key=lambda r: (r["date"], r["bench"], r["system"]))
    with open(HISTORY, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=HEADER, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_NONE, escapechar="\\")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in HEADER})
    print(f"history: {len(added)} rows added, {len(rows)} total")


if __name__ == "__main__":
    sys.exit(main())
