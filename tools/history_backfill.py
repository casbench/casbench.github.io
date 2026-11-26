#!/usr/bin/env python3
"""Backfill results/history.tsv from the git history of the results files.

    python3 -I tools/history_backfill.py

For every commit that changed results/ (oldest first) and every results file
whose content changed in that commit, one row is added, dated like
make_tables_history.jl dates a run: by the last block of the host's
machine.txt (at that commit) that names the bench and the system; the commit
hash is the source. Rows already present (same date, host, bench, system) are
kept. Files of the flat layout (results/<bench>_<system>.tsv, before
2026-11-20) belong to the host OLD_HOST.
"""
import csv
import io
import pathlib
import statistics
import subprocess
import sys

csv.field_size_limit(1 << 30)   # a Gröbner basis in the result column exceeds the default 128 KiB field

ROOT = pathlib.Path(__file__).resolve().parents[1]
HISTORY = ROOT / "results" / "history.tsv"
OLD_HOST = "giac-bench"      # the host of the flat layout, before results/<host>/
HEADER = ["date", "host", "bench", "system", "n", "verified", "wrong", "unverified", "unsolved", "unavailable", "error",
          "timeout", "t_warm_sum", "t_warm_median", "versions", "source"]
STATUSES = ("verified", "wrong", "unverified", "unsolved", "unavailable", "error", "timeout")
FIXED = {"host", "host_slug", "kernel", "cpu", "memory_GiB", "julia", "julia_threads", "bench", "system", "giac_version",
         "run_id", "harness_commit", "harness_dirty", "giac_jl_commit", "osr_commit", "load_avg", "calibration_s"}


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
    solved = {"verified", "verified_numeric", "verified_symbolic"}
    counts = {s: sum(r["status"] in solved if s == "verified" else r["status"] == s for r in rows) for s in STATUSES}
    tw = []
    for r in rows:
        if r["status"] in solved:
            try:
                v = float(r["t_warm_s"])
                if v == v:
                    tw.append(v)
            except ValueError:
                pass
    # Legacy snapshots retain their original metric. New-format snapshots
    # never aggregate heterogeneous operations into one median.
    modern = bool(rows) and "verify_status" in rows[0]
    ops = {r.get("op", "") for r in rows if r.get("op", "")}
    attempted = sum(r["status"] != "unavailable" for r in rows)
    eligible = (not modern or (len(ops) == 1 and attempted > 0 and
                2 * counts["verified"] >= attempted and len(tw) == counts["verified"]))
    return label, len(rows), counts, sum(tw), (statistics.median(tw) if tw and eligible else float("nan"))


def main():
    existing = []
    if HISTORY.exists():
        existing = list(csv.DictReader(open(HISTORY, newline="", encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE))
    seen = {(r["date"], r.get("host", OLD_HOST), r["bench"], r["system"]) for r in existing}
    commits = git("log", "--reverse", "--format=%H", "--", "results").split()
    last_blob = {}
    added = []
    for h in commits:
        # (host, file name) -> blob, for the flat layout (host OLD_HOST) and for results/<host>/
        tree = {}
        for line in git("ls-tree", "-r", h, "results/").splitlines():
            meta, path = line.split("\t", 1)
            rel = pathlib.Path(path).relative_to("results")
            host = rel.parts[0] if len(rel.parts) == 2 else OLD_HOST
            tree[(host, rel.name)] = (meta.split()[2], path)
        for host in sorted({hst for hst, _ in tree}):
            if (host, "machine.txt") not in tree:
                continue
            dates = run_dates(git("show", f"{h}:{tree[(host, 'machine.txt')][1]}"))
            for (hst, name), (blob, path) in sorted(tree.items()):
                if hst != host or not name.endswith(".tsv") or name == "history.tsv" or last_blob.get((host, name)) == blob:
                    continue
                last_blob[(host, name)] = blob
                parts = name[:-4].split("_", 2)
                if len(parts) < 3:
                    continue
                bench, system = parts[0] + "_" + parts[1], parts[2]
                label, n, counts, tsum, tmed = summarize(git("show", f"{h}:{path}"))
                d = dates.get((bench, label)) or dates.get((bench, system)) or dates.get((bench, ""))
                if d is None:
                    continue
                date, vers = d
                key = (date, host, bench, system)
                if key in seen:
                    continue
                added.append({"date": date, "host": host, "bench": bench, "system": system, "n": n, **counts,
                              "t_warm_sum": f"{tsum:.6g}", "t_warm_median": f"{tmed:.6g}", "versions": vers, "source": h[:12]})
                seen.add(key)
    rows = existing + added
    rows.sort(key=lambda r: (r["date"], r.get("host", OLD_HOST), r["bench"], r["system"]))
    with open(HISTORY, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=HEADER, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_NONE, escapechar="\\")
        w.writeheader()
        for r in rows:
            w.writerow({**{k: r.get(k, "") for k in HEADER}, "host": r.get("host", OLD_HOST)})
    print(f"history: {len(added)} rows added, {len(rows)} total")


if __name__ == "__main__":
    sys.exit(main())
