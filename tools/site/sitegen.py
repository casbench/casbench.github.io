#!/usr/bin/env python3
"""Generate the Hugo content of the project site from the repository.

    python3 -I tools/site/sitegen.py --root . --out DIR

writes DIR/content (Markdown pages for Hugo, theme Hextra) and DIR/static
(llms.txt). Nothing is written inside the repository: every page is derived
from results/*.tsv, results/machine.txt, results/environment.txt and
README.md on each build, so the site cannot drift from the results files.
See tools/site/build.sh.
"""
import argparse
import csv
import datetime
import html
import math
import pathlib
import re
import subprocess

REPO = "https://github.com/s-celles/computer-algebra-system-benchmarks"
BLOB = REPO + "/blob/main"
PAPER = "JuliaCon Proceedings paper on Giac.jl (in preparation, 2027)"

# bench key -> (title, one-line description)
BENCHES = {
    "A_ffi": ("A. FFI overhead", "Microseconds per call through each dispatch level of Giac.jl, minimum over rounds."),
    "B_cas": ("B. CAS operations", "expand, factor, integrate and simplify on 34 fixed inputs; every answer verified."),
    "C_ifactor": ("C. Integer factorisation", "Giac.ifactor, Primes.factor and LibPARI on Int64 values, smooth integers and semiprimes of 20 to 60 digits."),
    "D_coverage": ("D. Functional coverage", "One problem per capability: is the operation available, and is the answer right?"),
    "E_suite": ("E. Problem suite", "107 problems in thirteen categories, from the 103 of the fork notebook plus four model-to-Jacobian tasks."),
    "F_integration": ("F. Integration sample", "A stratified sample of the 12000.org independent integration tests, checked by differentiation."),
    "G_groebner": ("G. Gröbner bases", "Reduced Gröbner bases of classical systems (katsura, cyclic, eco, noon) over Q and a prime field."),
    "I_scale": ("I. Throughput at scale", "How the time grows with the size of the expression: dense expansion, a large derivative, a series, substitution, evaluation and code generation on random trees of up to a hundred thousand leaves."),
    "H_osr": ("H. OSR rules", "The integration rules of OpenSymbolicRules v1 as problems: every integrand, checked by differentiation and against the Lean-certified replacement."),
}
OSR = "https://opensymbolicrules.github.io/"
STATUSES = ("verified", "wrong", "unverified", "unsolved", "unavailable", "error", "timeout")
STATUS_HELP = {
    "verified": "returned and checked by a system-neutral test",
    "wrong": "returned, and the check failed",
    "unverified": "returned, but the check could not evaluate it",
    "unsolved": "returned unevaluated or incomplete, or the system declared that it cannot",
    "unavailable": "no operation of that kind in the system, as wired in its adapter",
    "error": "the call raised, or the worker crashed",
    "timeout": "over the per-case limit",
}
FIXED_KEYS = {"host", "kernel", "cpu", "memory_GiB", "julia", "julia_threads", "bench"}
# the supervisor records a timeout or a crash under the system key, not the label
SYSTEM_LABELS = {"giac": "Giac.jl", "symbolics": "Symbolics.jl", "sympy": "SymPy", "symj": "SymJ.jl",
                 "primes": "Primes.jl factor", "pari": "LibPARI.jl factors", "groebner": "Groebner.jl",
                 "msolve": "msolve (AlgebraicSolving.jl)", "maxima": "Maxima", "fricas": "FriCAS",
                 "sage_giac": "Sage/Giac", "sage_maxima": "Sage/Maxima", "sage_fricas": "Sage/FriCAS", "sage_sympy": "Sage/SymPy",
                 "sage_singular": "Sage/Singular", "macaulay2": "Macaulay2", "symengine": "SymEngine.jl"}
DISCLAIMER = ("An individual, non-commercial project. The numbers are dated: they were measured on a shared virtual "
              "machine with the package versions recorded in the results files, and the systems compared are moving "
              "quickly. A status is a claim to check against the results files, not a verdict on a system.")

WORKFLOW = """
Every bench follows the same path from fixed inputs to the pages of this site. The diagrams are the
contract of the repository: a number that is not produced this way is not reported.

## From inputs to results

```mermaid
flowchart LR
    I["inputs<br/>fixed in the repository<br/>(problems.jl, inputs.jl, tasks_&lt;system&gt;.jl)"] --> S
    S["lib/supervise.jl<br/>one Julia process per bench and system<br/>per-case time limit, restart after a crash"] --> W
    W["lib/worker.jl<br/>loads the adapter and the problem file"] --> A
    A["lib/adapters/&lt;system&gt;.jl<br/>OPS, EVAL, UNSOLVED, VERSIONS"] --> C
    C{"check<br/>plain Julia, system-neutral"} -->|verified / wrong / unverified| R
    A -->|missing operation| U[unavailable] --> R
    A -->|declined, unevaluated| N[unsolved] --> R
    S -->|limit, signal| T[timeout / error] --> R
    R[("results/&lt;bench&gt;_&lt;system&gt;.tsv<br/>status, first call, warm time, answer, note<br/>+ machine.txt, environment.txt")]
```

## From results to tables, figures and pages

```mermaid
flowchart LR
    R[("results/*.tsv")] --> M["make_tables.jl<br/>make_tables_E.jl"]
    M --> T["tables/*.tex"] & F["figures/E_times.tex"] & S["results/summary.md"]
    R --> G["tools/site/sitegen.py"] --> H["Hugo + Hextra<br/>.github/workflows/site.yml"] --> P["this site"]
    T & F -->|copied, submodule bumped| J["paper repository<br/>paper/tables, paper/figures"]
    CI["CI: make_tables.jl on the committed results<br/>must reproduce tables/, figures/ and summary.md"] -.-> T
```

## How a status is decided

```mermaid
flowchart TD
    Q[call the operation] --> X{raised?}
    X -->|declares it cannot| UN[unsolved]
    X -->|other exception| ER[error]
    X -->|no| O{answer}
    O -->|nothing, empty, unevaluated form| UN
    O -->|expression| K{system-neutral check}
    K -->|passes| V[verified]
    K -->|fails| WR[wrong]
    K -->|cannot evaluate| UV[unverified]
    Q -.->|over the limit| TO[timeout]
```

## Reproducing

```mermaid
sequenceDiagram
    participant U as you
    participant N as nix run (the bench app)
    participant J as julia (one process per bench and system)
    U->>N: git clone --recurse-submodules, then nix run the bench app
    N->>N: pin julia 1.13.3 and python3+sympy, record environment.txt
    N->>J: run_all.jl calls supervise(env, worker, bench, system, out, timeout)
    J-->>N: results/BENCH_SYSTEM.tsv
    N->>N: make_tables.jl
    N-->>U: tables/, figures/, results/summary.md
```
"""


def esc(s):
    return html.escape(str(s), quote=False)


def slug(idx, name):
    """Directory name of a case page: index and a short ASCII form of the case name."""
    t = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:48].rstrip("-")
    return f"{idx:03d}-{t}" if t else f"{idx:03d}"


def badge(status):
    cls = status if status in STATUSES else "other"
    return f'<span class="verdict verdict--{cls}" title="{esc(STATUS_HELP.get(status, status))}">{esc(status)}</span>'


def fmt_time(s):
    if s is None or isinstance(s, float) and math.isnan(s):
        return ""
    if s < 1e-3:
        return f"{s * 1e6:.0f} µs"
    if s < 1:
        return f"{s * 1e3:.1f} ms"
    return f"{s:.2f} s"


def front(title, weight=None, **extra):
    lines = ["---", f"title: {title!r}"]
    if weight is not None:
        lines.append(f"weight: {weight}")
    for k, v in extra.items():
        lines.append(f"{k}: {v!r}")
    lines.append("---")
    return "\n".join(lines) + "\n\n"


def read_tsv(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
            try:
                r["idx"] = int(r["idx"])
                r["t_first_s"] = float(r["t_first_s"])
                r["t_warm_s"] = float(r["t_warm_s"])
            except (KeyError, ValueError):
                continue
            rows.append(r)
    return rows


def etime(r):
    return r["t_warm_s"] if not math.isnan(r["t_warm_s"]) else r["t_first_s"]


def fence(text):
    """A text code block that cannot be broken by backticks in the content."""
    return "```text\n" + text.replace("```", "'''") + "\n```\n"


PALETTE = ["#1f77b4", "#d62728", "#2ca02c", "#9467bd", "#ff7f0e", "#8c564b", "#e377c2", "#17becf", "#7f7f7f", "#bcbd22"]


def read_history(path):
    """Rows of results/history.tsv (dates as ISO strings, numbers parsed)."""
    rows = []
    if not path.exists():
        return rows
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
            try:
                for k in ("n", "verified", "wrong", "unverified", "unsolved", "unavailable", "error", "timeout"):
                    r[k] = int(r[k])
                r["t_warm_median"] = float(r["t_warm_median"])
                r["t_warm_sum"] = float(r["t_warm_sum"])
            except (KeyError, ValueError):
                continue
            rows.append(r)
    rows.sort(key=lambda r: r["date"])
    return rows


def svg_chart(series, title, ylabel, log=False, width=720, height=260):
    """A line chart as inline SVG: series = {label: [(date, value), ...]}; dates are ISO strings, placed by time."""
    pts = [(d, v) for ps in series.values() for d, v in ps if v == v and (not log or v > 0)]
    if not pts:
        return f"<p><em>{esc(title)}: no data yet.</em></p>\n"
    def tnum(d):
        try:
            return datetime.datetime.fromisoformat(d.replace(" ", "T")).timestamp()
        except ValueError:
            return 0.0
    xs = [tnum(d) for d, _ in pts]
    x0, x1 = min(xs), max(xs)
    x1 = x1 if x1 > x0 else x0 + 86400
    vals = [math.log10(v) if log else v for _, v in pts]
    y0, y1 = min(vals), max(vals)
    if y1 <= y0:
        y0, y1 = (y0 - 1, y1 + 1) if log else (0, max(1, y1 * 1.1))
    if not log:
        y0 = 0
    ml, mr, mt, mb = 56, 16, 30, 46
    pw, ph = width - ml - mr, height - mt - mb
    X = lambda t: ml + (t - x0) / (x1 - x0) * pw
    Y = lambda v: mt + ph - ((math.log10(v) if log else v) - y0) / (y1 - y0) * ph
    out = [f'<svg class="chart" viewBox="0 0 {width} {height}" width="100%" role="img" aria-label="{esc(title)}">',
           f'<text x="{ml}" y="18" font-size="13" font-weight="600">{esc(title)}</text>']
    # y grid: 4 ticks
    for i in range(5):
        v = y0 + (y1 - y0) * i / 4
        y = mt + ph - ph * i / 4
        label = f"{10 ** v:.3g}" if log else f"{v:.0f}"
        out.append(f'<line x1="{ml}" y1="{y:.1f}" x2="{ml + pw}" y2="{y:.1f}" stroke="#ddd"/>'
                   f'<text x="{ml - 6}" y="{y + 4:.1f}" font-size="10" text-anchor="end">{label}</text>')
    out.append(f'<text x="12" y="{mt + ph / 2:.0f}" font-size="10" transform="rotate(-90 12 {mt + ph / 2:.0f})" text-anchor="middle">{esc(ylabel)}</text>')
    # x ticks: first, last and up to 3 between
    dates = sorted({d for d, _ in pts}, key=tnum)
    step = max(1, len(dates) // 4)
    for d in dates[::step] + ([dates[-1]] if dates[-1] not in dates[::step] else []):
        x = X(tnum(d))
        out.append(f'<line x1="{x:.1f}" y1="{mt + ph}" x2="{x:.1f}" y2="{mt + ph + 4}" stroke="#888"/>'
                   f'<text x="{x:.1f}" y="{mt + ph + 16}" font-size="10" text-anchor="middle">{esc(d[:10])}</text>')
    for i, (label, ps) in enumerate(series.items()):
        color = PALETTE[i % len(PALETTE)]
        ps = [(d, v) for d, v in sorted(ps, key=lambda q: tnum(q[0])) if v == v and (not log or v > 0)]
        if not ps:
            continue
        path = " ".join(f"{'M' if j == 0 else 'L'}{X(tnum(d)):.1f},{Y(v):.1f}" for j, (d, v) in enumerate(ps))
        out.append(f'<path d="{path}" fill="none" stroke="{color}" stroke-width="2"/>')
        for d, v in ps:
            out.append(f'<circle cx="{X(tnum(d)):.1f}" cy="{Y(v):.1f}" r="3" fill="{color}"><title>{esc(label)} {esc(d)}: {v:.4g}</title></circle>')
        lx = ml + (i % 4) * (pw / 4)
        ly = height - 8 - (i // 4) * 12
        out.append(f'<rect x="{lx:.0f}" y="{ly - 8}" width="10" height="10" fill="{color}"/><text x="{lx + 14:.0f}" y="{ly}" font-size="10">{esc(label)}</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


class Site:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.results = {}          # bench -> system -> [rows]
        for p in sorted((self.root / "results").glob("*.tsv")):
            for r in read_tsv(p):
                if r["case"] == "_load":
                    continue
                r["system"] = SYSTEM_LABELS.get(r["system"], r["system"])
                self.results.setdefault(r["bench"], {}).setdefault(r["system"], []).append(r)
        self.machine = self.read_machine()
        self.categories = self.read_categories()
        self.history = read_history(self.root / "results" / "history.tsv")
        self.generated = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        self.results_commit = self.git_results_commit()

    def git_results_commit(self):
        """(short hash, date) of the last commit that changed results/, or None outside a git checkout."""
        try:
            out = subprocess.run(["git", "log", "-1", "--format=%h %cI", "--", "results"], cwd=self.root,
                                 capture_output=True, text=True, check=True).stdout.split()
            return (out[0], out[1]) if len(out) == 2 else None
        except (OSError, subprocess.CalledProcessError):
            return None

    def stamp(self):
        s = f"Site generated {self.generated}"
        if self.last_date():
            s += f" · last run recorded {esc(self.last_date())}"
        if self.results_commit:
            s += f" · results commit {esc(self.results_commit[0])} ({esc(self.results_commit[1][:16].replace('T', ' '))})"
        return s

    # -- inputs -------------------------------------------------------------
    def read_machine(self):
        """Blocks of results/machine.txt: list of (date, {key: value})."""
        blocks = []
        p = self.root / "results" / "machine.txt"
        if not p.exists():
            return blocks
        for line in p.read_text(encoding="utf-8").splitlines():
            if line.startswith("# "):
                blocks.append((line[2:].strip(), {}))
            elif "\t" in line and blocks:
                k, v = line.split("\t", 1)
                blocks[-1][1][k] = v
        return blocks

    def read_categories(self):
        """Problem index -> category name for bench E, from E_suite/problems.jl."""
        p = self.root / "E_suite" / "problems.jl"
        if not p.exists():
            return {}
        txt = p.read_text(encoding="utf-8")
        m = re.search(r"const CAT = \[(.*?)\]\n", txt, re.S)
        names = re.findall(r'"([^"]+)"', m.group(1)) if m else []
        cats = {}
        for i, cm in enumerate(re.finditer(r'^\s+P\(CAT\[(\d+)\], "([^"]+)"', txt, re.M), 1):
            k = int(cm.group(1))
            cats[i] = names[k - 1] if 0 < k <= len(names) else str(k)
        return cats

    def versions(self):
        """Package -> (version, date), from the last machine block of each bench."""
        seen = {}
        for date, kv in self.machine:
            for k, v in kv.items():
                if k not in FIXED_KEYS:
                    seen[k] = (v.strip('"'), date)
        return seen

    def last_date(self):
        return max((d for d, _ in self.machine), default="")

    def ncases(self):
        return sum(len({r["case"] for rows in systems.values() for r in rows}) for systems in self.results.values())

    def systems(self):
        return sorted({s for systems in self.results.values() for s in systems})

    def packages(self):
        """Distinct packages behind the system columns (first word of the label)."""
        return sorted({s.split()[0] for s in self.systems()})

    def by_case(self, key):
        """Case index -> {"case", "op", system: row} for a bench."""
        by_idx = {}
        for s in sorted(self.results[key]):
            for r in self.results[key][s]:
                by_idx.setdefault(r["idx"], {"case": r["case"], "op": r["op"]})[s] = r
        return by_idx

    # -- pages --------------------------------------------------------------
    def home(self):
        nb, ns, nc = len(self.results), len(self.packages()), self.ncases()
        out = front("Computer algebra system benchmarks", 0)
        out += '<p class="project-kicker">reproducible · verified · dated</p>\n\n'
        out += f'<p class="site-stamp">{self.stamp()}</p>\n\n'
        out += ("Benchmarks of computer algebra systems: Julia packages (Giac.jl, Symbolics.jl, SymJ.jl, Groebner.jl, Primes.jl, "
                "LibPARI.jl, msolve through AlgebraicSolving.jl), Python's SymPy, and Maxima, FriCAS, SageMath and Macaulay2 driven "
                "as processes from the same harness. Every number comes from a script in the "
                "repository, run on fixed inputs, with every answer checked by a system-neutral test and every run dated. "
                f"They are the reproduced numbers of the {PAPER}.\n\n")
        out += '<div class="suite-stats">\n'
        for n, label, href in ((nb, "benches", "results/"), (ns, "packages", "systems/"),
                               (nc, "cases", "results/"), (self.last_date()[:10] or "n/a", "last run", "environment/")):
            out += f'<a class="suite-stat" href="{href}"><strong>{esc(n)}</strong><span>{label}</span></a>\n'
        out += "</div>\n\n"
        out += f'<div class="disclaimer">{esc(DISCLAIMER)}</div>\n\n'
        out += "## Benches\n\n| bench | what it measures |\n|---|---|\n"
        for key, (title, desc) in BENCHES.items():
            if key in self.results:
                out += f"| [{title}](results/{key.lower()}/) | {desc} |\n"
        out += ("\n## Sources\n\n"
                "- Bench E follows the notebook of a fork of Giac.jl; bench F samples the 12000.org independent integration tests "
                "(Nasser M. Abbasi; the problems come from the Rubi test suite and other collections); bench G uses the classical "
                "systems of Groebner.jl's examples.\n"
                f"- Bench H consumes [OpenSymbolicRules]({OSR}) (OSR): the v1 integration rules, with their Lean verdicts and "
                "conditions, pinned as the git submodule `osr/Integration`. These benchmarks are a consumer of OSR; the "
                "conformance suites of OSR are the next source.\n")
        out += "\n## Status vocabulary\n\n| status | meaning |\n|---|---|\n"
        for s in STATUSES:
            out += f"| {badge(s)} | {STATUS_HELP[s]} |\n"
        out += (f"\n[History](history/) · [Workflow](workflow/) · [Methodology](methodology/) · [Systems and versions](systems/) · "
                f"[Machine](environment/) · [Repository]({REPO}) · Code MIT, data and pages CC BY 4.0\n")
        return out

    def results_index(self):
        out = front("Results", 1)
        out += "Counts per bench and system, from `results/<bench>_<system>.tsv`. Click a bench for every case, and a case for every answer.\n\n"
        for key, systems in self.results.items():
            title, desc = BENCHES.get(key, (key, ""))
            out += f"### [{title}]({key.lower()}/)\n\n{desc}\n\n"
            statuses = [s for s in STATUSES if any(r["status"] == s for rows in systems.values() for r in rows)]
            out += "| system | cases | " + " | ".join(statuses) + " | warm time, sum |\n|---|---|" + "---|" * (len(statuses) + 1) + "\n"
            for system, rows in sorted(systems.items()):
                counts = {s: sum(r["status"] == s for r in rows) for s in statuses}
                tsum = sum(r["t_warm_s"] for r in rows if r["status"] == "verified" and not math.isnan(r["t_warm_s"]))
                out += f"| {esc(system)} | {len(rows)} | " + " | ".join(str(counts[s]) for s in statuses) + f" | {fmt_time(tsum)} |\n"
            out += "\n"
        return out

    def bench_page(self, key, weight):
        systems = self.results[key]
        title, desc = BENCHES.get(key, (key, ""))
        names = sorted(systems)
        out = front(title, weight, linkTitle=title.split(". ", 1)[-1])
        out += f"{desc} Source: [`{key}/`]({BLOB}/{key}), results: [`results/`]({BLOB}/results).\n\n"
        out += "Time shown: the minimum over repeated calls (warm), else the first call. Type to filter, click a heading to sort, click a case for every answer.\n\n"
        by_idx = self.by_case(key)
        out += '<div class="filterable">\n\n'
        cat = key == "E_suite" and self.categories
        out += "| # | case |" + (" category |" if cat else "") + " op | " + " | ".join(esc(s) for s in names) + " |\n"
        out += "|---|---|" + ("---|" if cat else "") + "---|" + "---|" * len(names) + "\n"
        for i in sorted(by_idx):
            e = by_idx[i]
            cells = []
            for s in names:
                r = e.get(s)
                if r is None:
                    cells.append("")
                elif r["status"] == "unavailable":
                    cells.append(badge("unavailable"))
                else:
                    t = fmt_time(etime(r)) if r["status"] in ("verified", "wrong", "unverified", "unsolved") else ""
                    cells.append(badge(r["status"]) + (f" {t}" if t else ""))
            out += (f"| {i} | [{esc(e['case'])}]({slug(i, e['case'])}/) |" + (f" {esc(self.categories.get(i, ''))} |" if cat else "")
                    + f" `{esc(e['op'])}` | " + " | ".join(cells) + " |\n")
        out += "\n</div>\n"
        return out

    def case_pages(self, key):
        """(directory, markdown) for every case of a bench: the statement, then each system's answer."""
        title, _ = BENCHES.get(key, (key, ""))
        pages = []
        for i, e in sorted(self.by_case(key).items()):
            name = e["case"]
            systems = [s for s in sorted(self.results[key]) if s in e]
            out = front(f"{i}. {name}", i, linkTitle=f"{i}. {name}"[:60])
            out += f"[{title}](../) · operation `{esc(e['op'])}`"
            if key == "E_suite" and i in self.categories:
                out += f" · category *{esc(self.categories[i])}*"
            out += "\n\n"
            asked = sorted({e[s]["note"] for s in systems if e[s]["note"] and e[s]["status"] in ("verified", "wrong", "unverified", "unsolved")})
            if asked:
                out += f"**What is asked.** {esc(asked[0])}\n\n"
            out += "| system | status | first call | warm |\n|---|---|---|---|\n"
            for s in systems:
                r = e[s]
                out += f"| {esc(s)} | {badge(r['status'])} | {fmt_time(r['t_first_s'])} | {fmt_time(r['t_warm_s'])} |\n"
            out += "\n## Answers\n\n"
            for s in systems:
                r = e[s]
                out += f"### {esc(s)} {badge(r['status'])}\n\n"
                if r["result"]:
                    out += fence(r["result"]) + "\n"
                if r["note"]:
                    out += f"*{esc(r['note'])}*\n\n"
                if not r["result"] and not r["note"]:
                    out += "*(nothing returned)*\n\n"
            pages.append((slug(i, name), out))
        return pages

    def systems_page(self):
        out = front("Systems", 2)
        out += ("The systems, as pinned by the `Project.toml` and `Manifest.toml` of each environment under "
                f"[`envs/`]({BLOB}/envs). Versions below are those recorded in `results/machine.txt` at run time.\n\n")
        out += "| package | version | recorded |\n|---|---|---|\n"
        for k, (v, d) in sorted(self.versions().items(), key=lambda kv: kv[0].lower()):
            out += f"| {esc(k)} | `{esc(v[:90])}` | {esc(d[:10])} |\n"
        out += ("\n## Adapters\n\n`lib/adapters/<system>.jl` give the systems the same small interface "
                "(`OPS`, `EVAL`, `NTERMS`, `NFACTORS`, `UNSOLVED`, `VERSIONS`). Bench E has one task file per system, "
                "`E_suite/tasks_<system>.jl`, written the way that system's user would write it. An operation an adapter "
                "maps to `missing` is reported as *unavailable*.\n")
        return out

    def environment_page(self):
        out = front("Environment", 3)
        first = self.machine[0][1] if self.machine else {}
        out += "The machine, from the first block of `results/machine.txt`:\n\n| key | value |\n|---|---|\n"
        for k in ("host", "kernel", "cpu", "memory_GiB", "julia", "julia_threads"):
            if k in first:
                out += f"| {k} | `{esc(first[k])}` |\n"
        out += f"\nRuns recorded: {len(self.machine)} blocks, from {esc(min((d for d, _ in self.machine), default=''))} to {esc(self.last_date())}.\n\n"
        env = self.root / "results" / "environment.txt"
        if env.exists():
            out += "## environment.txt\n\n" + fence(env.read_text(encoding="utf-8").strip())
        return out

    def history_page(self):
        out = front("History", 4)
        out += (f'<p class="site-stamp">{self.stamp()}</p>\n\n'
                "Every run of every bench and system, from `results/history.tsv` (one row per bench, system and run date; "
                "appended by `make_tables.jl`, backfilled from the git history by `tools/history_backfill.py`). "
                "Verified counts and median warm times over the verified cases; hover a point for its value.\n\n")
        if not self.history:
            return out + "*No history yet.*\n"
        benches = [b for b in BENCHES if any(r["bench"] == b for r in self.history)] + \
                  sorted({r["bench"] for r in self.history} - set(BENCHES))
        for b in benches:
            title = BENCHES.get(b, (b, ""))[0]
            rows = [r for r in self.history if r["bench"] == b]
            systems = sorted({r["system"] for r in rows})
            lab = lambda s: SYSTEM_LABELS.get(s, s)
            out += f"## {esc(title)}\n\n"
            out += svg_chart({lab(s): [(r["date"], r["verified"]) for r in rows if r["system"] == s] for s in systems},
                             f"{title}: verified cases per run", "verified")
            out += svg_chart({lab(s): [(r["date"], r["t_warm_median"]) for r in rows if r["system"] == s] for s in systems},
                             f"{title}: median warm time of the verified cases (s, log)", "seconds", log=True)
            out += "<details><summary>runs</summary>\n\n| date | system | n | verified | wrong | unverified | unsolved | unavailable | error | timeout | median warm | source |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
            for r in rows:
                out += (f"| {esc(r['date'][:16].replace('T', ' '))} | {esc(lab(r['system']))} | {r['n']} | {r['verified']} | {r['wrong']} | {r['unverified']} | "
                        f"{r['unsolved']} | {r['unavailable']} | {r['error']} | {r['timeout']} | {fmt_time(r['t_warm_median'])} | `{esc(r['source'])}` |\n")
            out += "\n</details>\n\n"
        return out

    def workflow(self):
        return front("Workflow", 5) + WORKFLOW.strip() + "\n"

    def methodology(self):
        parts = []
        for rel in ("docs/methodology.md", "docs/benches.md"):
            p = self.root / rel
            if not p.exists():
                continue
            body = re.sub(r"^# .*\n", "", p.read_text(encoding="utf-8"), count=1)
            body = re.sub(r"\]\((?!https?://|#)([^)]+)\)", lambda m: f"]({BLOB}/docs/{m.group(1)})", body)
            parts.append(f"From [`{rel}`]({BLOB}/{rel}).\n\n" + body)
        return front("Methodology", 6) + "\n\n---\n\n".join(parts)

    def llms(self):
        return (f"# Computer algebra system benchmarks\n\n> Reproducible, verified, dated benchmarks of computer algebra systems (Julia packages, SymPy, Maxima, FriCAS, SageMath, Macaulay2). {DISCLAIMER}\n\n- Consumes OpenSymbolicRules (OSR): {OSR}\n"
                + "\n".join(f"- {t}: {d}" for k, (t, d) in BENCHES.items() if k in self.results) + f"\n- Repository: {REPO}\n")


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def generate(root, out):
    site = Site(root)
    c, s = pathlib.Path(out) / "content", pathlib.Path(out) / "static"
    write(c / "_index.md", site.home())
    write(c / "results" / "_index.md", site.results_index())
    for w, key in enumerate(site.results, 1):
        write(c / "results" / key.lower() / "_index.md", site.bench_page(key, w))
        for d, text in site.case_pages(key):
            write(c / "results" / key.lower() / d / "_index.md", text)
    write(c / "systems" / "_index.md", site.systems_page())
    write(c / "environment" / "_index.md", site.environment_page())
    write(c / "history" / "_index.md", site.history_page())
    write(c / "workflow" / "_index.md", site.workflow())
    write(c / "methodology" / "_index.md", site.methodology())
    write(s / "llms.txt", site.llms())
    return site


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=".")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    site = generate(a.root, a.out)
    print(f"site content: {a.out}/content ({len(site.results)} benches, {site.ncases()} cases)")


if __name__ == "__main__":
    main()
