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
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import latexify  # noqa: E402

REPO = "https://github.com/s-celles/computer-algebra-system-benchmarks"
BLOB = REPO + "/blob/main"
PAPER = "JuliaCon Proceedings paper on Giac.jl (in preparation, 2027)"

# bench key -> (title, one-line description)
BENCHES = {
    "A_ffi": ("A. FFI overhead", "Microseconds per call through each dispatch level of Giac.jl, minimum over rounds."),
    "B_cas": ("B. CAS operations", "expand, factor, integrate and simplify on fixed inputs; every answer verified."),
    "C_ifactor": ("C. Integer factorisation", "Giac.ifactor, Primes.factor and LibPARI on Int64 values, smooth integers and semiprimes of 20 to 60 digits."),
    "D_coverage": ("D. Functional coverage", "One problem per capability: is the operation available, and is the answer right?"),
    "E_suite": ("E. Problem suite", "The problems of the fork notebook, in categories from arithmetic to transforms and modelling, plus four model-to-Jacobian tasks."),
    "F_integration": ("F. Integration sample", "A stratified sample of the 12000.org independent integration tests, checked by differentiation."),
    "G_groebner": ("G. Gröbner bases", "Reduced Gröbner bases of classical systems (katsura, cyclic, eco, noon) over Q and a prime field."),
    "H_osr": ("H. OSR rules", "The integration rules of OpenSymbolicRules v1 as problems: every integrand, checked by differentiation and against the Lean-certified replacement."),
    "I_scale": ("I. Throughput at scale", "How the time grows with the size of the expression: dense expansion, a large derivative, a series, substitution, evaluation and code generation on random trees of up to a hundred thousand leaves."),
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
                 "sage_singular": "Sage/Singular", "macaulay2": "Macaulay2", "symengine": "SymEngine.jl", "computeengine": "Compute Engine"}


def package(label):
    """(kind, name) of what a system column measures: the Julia package (the first word, when it ends in .jl:
    "Primes.jl factor" is Primes.jl) or the other system ("msolve (AlgebraicSolving.jl)" is msolve, every
    Sage/<engine> column is SageMath driving that engine)."""
    w = label.split()[0]
    if w.endswith(".jl"):
        return ("julia", w)
    if label.startswith("Sage/"):
        return ("external", "SageMath")
    return ("external", label.split(" (")[0].strip())




def read_disclosures(path):
    """Rows of docs/disclosures.tsv, the conflict of interest declarations of the contributors
    (contributor, orcid, project, kind, role, note); every contributor writes their own rows."""
    rows = []
    if not path.exists():
        return rows
    with open(path, newline="", encoding="utf-8") as f:
        lines = [l for l in f if not l.startswith("#")]
    for r in csv.DictReader(lines, delimiter="\t", quoting=csv.QUOTE_NONE):
        if r.get("contributor") and r.get("project"):
            rows.append({k: (v or "").strip() for k, v in r.items()})
    return rows
DISCLAIMER = ("An individual, non-commercial project. The numbers are dated: they were measured on a shared virtual "
              "machine with the package versions recorded in the results files, and the systems compared are moving "
              "quickly. A status is a claim to check against the results files, not a verdict on a system: an unsolved "
              "or wrong case may hide an error of the benchmark itself, a command generated wrongly for that system, "
              "which is why every case page shows the exact input sent to each system next to its output. Corrections "
              "are welcome.")

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
            r.setdefault("input", "")
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


def svg_dotplot(by_idx, systems, categories=None, title="", width=760):
    """A dot plot: one row per case, time on a log x axis, one marker per system; filled when verified,
    hollow when the system returned something it did not solve, absent when it has no such operation."""
    solved = ("verified",)
    shown = ("verified", "wrong", "unverified", "unsolved", "error", "timeout")
    rows = sorted(by_idx)
    times = [etime(r) for i in rows for s in systems if (r := by_idx[i].get(s)) and r["status"] in shown and etime(r) == etime(r) and etime(r) > 0]
    if not times:
        return ""
    x0, x1 = math.log10(min(times)), math.log10(max(times))
    x1 = x1 if x1 > x0 else x0 + 1
    rh = 9
    ml, mr, mt, mb = 230, 110, 34, 30
    pw = width - ml - mr
    height = mt + rh * len(rows) + mb
    X = lambda t: ml + (math.log10(t) - x0) / (x1 - x0) * pw
    out = [f'<svg class="chart dotplot" viewBox="0 0 {width} {height}" width="100%" role="img" aria-label="{esc(title)}">',
           f'<text x="{ml}" y="16" font-size="12" font-weight="600">{esc(title)}</text>']
    # x grid at powers of ten
    for e in range(math.floor(x0), math.ceil(x1) + 1):
        x = X(10 ** e)
        if ml <= x <= ml + pw:
            out.append(f'<line x1="{x:.1f}" y1="{mt}" x2="{x:.1f}" y2="{mt + rh * len(rows)}" stroke="#ddd"/>'
                       f'<text x="{x:.1f}" y="{height - 12}" font-size="10" text-anchor="middle">1e{e}</text>')
    out.append(f'<text x="{ml + pw / 2:.0f}" y="{height - 1}" font-size="10" text-anchor="middle">seconds (warm, else first call)</text>')
    prev_cat = None
    for k, i in enumerate(rows):
        y = mt + rh * k + rh / 2
        e = by_idx[i]
        cat = categories.get(i) if categories else None
        if categories and cat != prev_cat:
            k > 0 and out.append(f'<line x1="{ml}" y1="{mt + rh * k:.1f}" x2="{ml + pw}" y2="{mt + rh * k:.1f}" stroke="#999"/>')
            out.append(f'<text x="{ml + pw + 6}" y="{y + 3:.1f}" font-size="9" fill="#555">{esc(cat)}</text>')
            prev_cat = cat
        label = e["case"] if len(e["case"]) <= 40 else e["case"][:38] + "…"
        out.append(f'<text x="{ml - 6}" y="{y + 3:.1f}" font-size="8" text-anchor="end">{esc(label)}</text>')
        for j, sname in enumerate(systems):
            r = e.get(sname)
            if r is None or r["status"] not in shown:
                continue
            t = etime(r)
            if not (t == t and t > 0):
                t = 10 ** x1
            color = PALETTE[j % len(PALETTE)]
            fill = color if r["status"] in solved else "none"
            out.append(f'<circle cx="{X(t):.1f}" cy="{y:.1f}" r="2.6" fill="{fill}" stroke="{color}" stroke-width="1.2">'
                       f'<title>{esc(sname)} · {esc(e["case"])} · {esc(r["status"])} · {fmt_time(t)}</title></circle>')
    for j, sname in enumerate(systems):
        lx = ml + j * (pw / max(1, len(systems)))
        out.append(f'<circle cx="{lx + 5:.0f}" cy="27" r="3" fill="{PALETTE[j % len(PALETTE)]}"/><text x="{lx + 12:.0f}" y="30" font-size="10">{esc(sname)}</text>')
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
        self._task_cache = {}
        self.history = read_history(self.root / "results" / "history.tsv")
        self.disclosures = read_disclosures(self.root / "docs" / "disclosures.tsv")
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

    def statement_tex(self, key, idx, name):
        """Display LaTeX of the problem, or None: bench E from E_suite/statements.tsv (the fork notebook's statements),
        F and H from the integrand text of their input files, G from the polynomial system, B, D, I from the case name."""
        if key == "E_suite":
            if not hasattr(self, "_e_tex"):
                self._e_tex = {}
                p = self.root / "E_suite" / "statements.tsv"
                if p.exists():
                    k = 0
                    for line in p.read_text(encoding="utf-8").splitlines():
                        if line.startswith("#") or line.startswith("name\t") or "\t" not in line:
                            continue
                        k += 1
                        n, l = line.split("\t", 1)
                        self._e_tex[k] = (n, l)     # one row per problem, in the order of E_suite/problems.jl
            row = self._e_tex.get(idx)
            return row[1] if row and row[0] == name else None
        if key == "F_integration":
            if not hasattr(self, "_f_rows"):
                self._f_rows = {}
                p = self.root / "F_integration" / "sample.tsv"
                if p.exists():
                    for line in p.read_text(encoding="utf-8").splitlines()[1:]:
                        f = line.split("\t")
                        if len(f) == 7:
                            self._f_rows[int(f[0])] = (f[3], f[4], f[6])
                row = self._f_rows.get(idx)
            else:
                row = self._f_rows.get(idx)
            if row:
                lhs = latexify.integral(row[0], row[1])
                rhs = latexify.latexify(row[2]) if "Unintegrable" not in row[2] and "CannotIntegrate" not in row[2] else None
                return (lhs + " = " + rhs) if lhs and rhs and len(rhs) < 400 else lhs
            return None
        if key == "H_osr":
            if not hasattr(self, "_h_rows"):
                self._h_rows = {}
                p = self.root / "H_osr" / "rules.tsv"
                if p.exists():
                    for line in p.read_text(encoding="utf-8").splitlines():
                        f = line.split("\t")
                        if len(f) == 9 and not line.startswith(("#", "id\t")):
                            self._h_rows[f[0]] = f[5]
            rid = name.split(" ", 1)[0]
            integrand = self._h_rows.get(rid)
            return latexify.integral(integrand) if integrand else None
        if key == "G_groebner":
            if not hasattr(self, "_g_sys"):
                self._g_sys = {}
                p = self.root / "G_groebner" / "inputs.jl"
                if p.exists():
                    txt = p.read_text(encoding="utf-8")
                    for m in re.finditer(r'name = "([^"]+)", vars = \[([^\]]*)\],\s*polys = \[(.*?)\]\)', txt, re.S):
                        polys = re.findall(r'"([^"]+)"', m.group(3))
                        self._g_sys[m.group(1)] = polys
            sysname = name.split(" over ")[0]
            polys = self._g_sys.get(sysname)
            if polys:
                return "\\begin{aligned}" + " \\\\ ".join(latexify.latexify(q.replace("//", "/")) + " &= 0" for q in polys[:12]) + \
                       (" \\\\ \\ldots" if len(polys) > 12 else "") + "\\end{aligned}"
            return None
        # B, D, I: "op expression" in the case name
        parts = name.split(" ", 1)
        if len(parts) == 2 and parts[0].isalpha():
            t = latexify.latexify(parts[1])
            if not t.startswith("\\text{"):
                return "\\operatorname{" + parts[0] + "}\\left(" + t + "\\right)"
        return None

    def task_sources(self, key):
        """system label -> {case name: source text} from the task files (bench E) or the problem file (B, D, I):
        the code the adapter runs for the case, shown when the run recorded no input."""
        if key in self._task_cache:
            return self._task_cache[key]
        out = {}
        if key == "E_suite":
            for sk, label in (("giac", "Giac.jl"), ("sympy", "SymPy"), ("symbolics", "Symbolics.jl"), ("symj", "SymJ.jl")):
                p = self.root / "E_suite" / f"tasks_{sk}.jl"
                if not p.exists():
                    continue
                txt = p.read_text(encoding="utf-8")
                d = {}
                if sk == "giac":
                    for m in re.finditer(r'^task!\("((?:[^"\\]|\\.)*)",\s*(.*?)(?=^task!\(|\Z)', txt, re.M | re.S):
                        src = m.group(2).strip()
                        d[m.group(1)] = (src[:-1] if src.endswith(")") else src).strip()   # the closing paren of task!(
                else:
                    for m in re.finditer(r'^    "((?:[^"\\]|\\.)*)" => (.*?)(?=^    "(?:[^"\\]|\\.)*" =>|^\)|\Z)', txt, re.M | re.S):
                        d[m.group(1)] = m.group(2).strip().rstrip(",").strip()
                out[label] = d
        else:
            p = self.root / key / "problems.jl"
            if p.exists():
                txt = p.read_text(encoding="utf-8")
                d = {}
                for m in re.finditer(r'^\s+P\((?:CAT\[\d+\], )?"((?:[^"\\]|\\.)*)",\s*(.*?)(?=^\s+P\(|^\]|\Z)', txt, re.M | re.S):
                    d[m.group(1)] = "P(\"" + m.group(1) + "\", " + m.group(2).strip().rstrip(",").strip()
                for label in SYSTEM_LABELS.values():
                    out[label] = d
        self._task_cache[key] = out
        return out

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

    def ncases_by_bench(self):
        """Bench -> number of cases, a case being an index of the bench (two cases may share a name) counted once
        whatever the number of systems that ran it."""
        return {key: len({r["idx"] for rows in systems.values() for r in rows}) for key, systems in self.results.items()}

    def ncases(self):
        return sum(self.ncases_by_bench().values())

    def systems(self):
        return sorted({s for systems in self.results.values() for s in systems})

    def packages(self):
        """Distinct packages and systems behind the system columns."""
        return sorted({package(s)[1] for s in self.systems()})

    def packages_by_kind(self):
        """{"julia": [Julia packages], "external": [other systems]} behind the system columns of the results."""
        out = {"julia": set(), "external": set()}
        for s in self.systems():
            kind, name = package(s)
            out[kind].add(name)
        return {k: sorted(v) for k, v in out.items()}

    def systems_sentence(self):
        """The systems of the results in words: 'Julia packages (A, B) and other systems (C, SageMath driving D and E)'."""
        pk = self.packages_by_kind()
        engines = sorted({s.split("/", 1)[1] for s in self.systems() if s.startswith("Sage/")})
        ext = [f"SageMath driving {', '.join(engines)}" if n == "SageMath" and engines else n for n in pk["external"]]
        parts = []
        if pk["julia"]:
            parts.append(f"Julia packages ({', '.join(pk['julia'])})")
        if ext:
            parts.append(f"other systems ({'; '.join(ext)}) driven as processes from the same harness")
        return " and ".join(parts) if parts else "no system yet"

    def system_key(self, key, label):
        """The file key of a system label: results/<bench>_<key>.tsv (the inverse of SYSTEM_LABELS, else the label itself)."""
        for k, v in SYSTEM_LABELS.items():
            if v == label and (self.root / "results" / f"{key}_{k}.tsv").exists():
                return k
        for p in (self.root / "results").glob(f"{key}_*.tsv"):
            rows = read_tsv(p)
            if rows and SYSTEM_LABELS.get(rows[-1]["system"], rows[-1]["system"]) == label:
                return p.name[len(key) + 1:-4]
        return label.lower()

    def by_case(self, key):
        """Case index -> {"case", "op", system: row} for a bench."""
        by_idx = {}
        for s in sorted(self.results[key]):
            for r in self.results[key][s]:
                by_idx.setdefault(r["idx"], {"case": r["case"], "op": r["op"]})[s] = r
        return by_idx

    # -- pages --------------------------------------------------------------
    def home(self):
        nb, nc, pk = len(self.results), self.ncases(), self.packages_by_kind()
        out = front("Computer algebra system benchmarks", 0)
        out += '<p class="project-kicker">reproducible · verified · dated</p>\n\n'
        out += f'<p class="site-stamp">{self.stamp()}</p>\n\n'
        out += (f"Benchmarks of computer algebra systems, {self.systems_sentence()}: the systems named here are those "
                "present in the committed results files. Every number comes from a script in the "
                "repository, run on fixed inputs, with every answer checked by a system-neutral test and every run dated. "
                f"They are the reproduced numbers of the {PAPER}.\n\n")
        out += '<div class="suite-stats">\n'
        for n, label, href in ((nb, "benches", "results/"), (len(pk["julia"]), "Julia packages", "systems/"),
                               (len(pk["external"]), "other systems", "systems/"),
                               (nc, "cases", "results/"), (self.last_date()[:10] or "n/a", "last run", "environment/")):
            out += f'<a class="suite-stat" href="{href}"><strong>{esc(n)}</strong><span>{label}</span></a>\n'
        out += "</div>\n\n"
        out += f'<div class="disclaimer">{esc(DISCLAIMER)}</div>\n\n'
        out += f"{self.coi_summary()} Every contributor's declaration and the relation to every system are on the [conflict of interest](conflict-of-interest/) page.\n\n"
        ncb = self.ncases_by_bench()
        out += (f"## Benches\n\nThe {nc} cases are the sum of the cases column: a case is counted once per bench, "
                "whatever the number of systems that ran it. A bench without a committed results file is listed without a count.\n\n"
                "| bench | cases | systems | what it measures |\n|---|---|---|---|\n")
        for key, (title, desc) in BENCHES.items():
            if key in self.results:
                out += f"| [{title}](results/{key.lower()}/) | {ncb[key]} | {len(self.results[key])} | {desc} |\n"
            else:
                out += f"| {title} | no run committed yet | | {desc} |\n"
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
        out += self.cite_section()
        out += (f"\n[Data](data/) · [History](history/) · [Workflow](workflow/) · [Methodology](methodology/) · [Systems and versions](systems/) · "
                f"[Machine](environment/) · [Repository]({REPO}) · Code MIT, data and pages CC BY 4.0\n")
        return out

    def cite_section(self):
        """'How to cite', from CITATION.cff and the date of the last run (the data are dated: the citation says which run)."""
        c = read_citation(self.root / "CITATION.cff")
        if not c["authors"]:
            return ""
        names = []
        for a in c["authors"]:
            n = f"{a.get('given-names', '')} {a.get('family-names', '')}".strip()
            names.append(f"{esc(n)} ([ORCID {esc(a['orcid'].rsplit('/', 1)[-1])}]({esc(a['orcid'])}))" if a.get("orcid") else esc(n))
        year = (self.last_date() or self.generated)[:4]
        last = [a.get("family-names", "") for a in c["authors"]]
        bib_authors = " and ".join(f"{a.get('family-names', '')}, {a.get('given-names', '')}" for a in c["authors"])
        key = f"{(last[0] or 'casbench').lower()}{year}casbench"
        run = self.last_date()[:10]
        out = ("\n## How to cite\n\n"
               f"{', '.join(names)}. *{esc(c['title'])}*. {esc(year)}. "
               f"Repository: {esc(c['repository-code'] or REPO)}; site: {esc(c['url'])}. "
               f"The numbers are dated: cite the run you used ({esc(run)} is the last one on this build). "
               f"Licences: {esc(', '.join(c['license']))} (code MIT, data and pages CC BY 4.0). "
               f"The same metadata are in [`CITATION.cff`]({BLOB}/CITATION.cff), which GitHub renders as APA and BibTeX.\n\n"
               "```bibtex\n"
               f"@misc{{{key},\n  author = {{{bib_authors}}},\n  title = {{{c['title']}}},\n  year = {{{year}}},\n"
               f"  howpublished = {{\\url{{{c['url'] or REPO}}}}},\n  note = {{Repository {c['repository-code'] or REPO}; run of {run}}}\n}}\n"
               "```\n")
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
        out += ("Time shown: the minimum over repeated calls (warm; for a system run as a process, its own in-process time of "
                "the single call), else the first call. Type to filter, click a heading to sort, click a case for every answer.\n\n")
        raw = ", ".join(f"[{esc(s)}](../../data/{key}_{self.system_key(key, s)}.tsv)" for s in names)
        out += f"Raw data (TSV, one file per system): {raw}; [all benches](../../data/results.zip); [every file](../../data/).\n\n"
        by_idx = self.by_case(key)
        if len(names) > 1:
            out += ("Every case's time for every system, on a log scale: a filled mark is a verified answer, a hollow one a "
                    "case the system did not solve (wrong, unverified, unsolved, error or timeout) at the time it took, "
                    "no mark an operation the system does not have.\n\n")
            out += svg_dotplot(by_idx, names, self.categories if key == "E_suite" else None, f"{title}: time per case and system")
            out += "\n"
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
            # the problem's own note is the one most systems share; error messages are each system's own
            notes = [e[s]["note"] for s in systems if e[s]["note"] and not e[s]["note"].startswith(("check raised", "worker ", "rerun"))]
            asked = [n for n, _ in __import__("collections").Counter(notes).most_common(1)]
            if asked:
                out += f"**What is asked.** {esc(asked[0])}\n\n"
            out += "| system | status | first call | warm |\n|---|---|---|---|\n"
            for s in systems:
                r = e[s]
                out += f"| {esc(s)} | {badge(r['status'])} | {fmt_time(r['t_first_s'])} | {fmt_time(r['t_warm_s'])} |\n"
            out += "\n## Problem\n\n"
            tex = self.statement_tex(key, i, name)
            if tex:
                out += "$$" + tex + "$$\n\n"
            out += (f"{esc(asked[0])}\n\n" if asked else "") + (
                "The same problem is given to every system through its own adapter. For each system below, **Input** is what "
                "the benchmark sent (the system's own syntax, as recorded during the run; else the task or problem source the "
                "adapter runs) and **Output** is what came back. A status may hide a wrongly generated input, which is an error "
                "of the benchmark, not of the system.\n\n")
            sources = self.task_sources(key)
            for s in systems:
                r = e[s]
                out += f"## {esc(s)} {badge(r['status'])}\n\n#### Input\n\n"
                if r.get("input"):
                    out += fence(r["input"].replace(" ⏎ ", "\n")) + "\n"
                else:
                    src = sources.get(s, {}).get(name)
                    if src:
                        out += "*From the task source (the run recorded no input):*\n\n" + fence(src) + "\n"
                    else:
                        out += "*Not recorded in this run (files written before 2026-11-20 have no input column).*\n\n"
                out += "#### Output\n\n"
                if r["result"]:
                    out += fence(r["result"]) + "\n"
                elif r["status"] in ("unavailable",):
                    out += "*No such operation in this system (as wired in its adapter).*\n\n"
                else:
                    out += "*(nothing returned)*\n\n"
                if r["note"]:
                    out += f"*Check: {esc(r['note'])}*\n\n"
            pages.append((slug(i, name), out))
        return pages

    def systems_page(self):
        out = front("Systems", 2)
        out += ("The systems, as pinned by the `Project.toml` and `Manifest.toml` of each environment under "
                f"[`envs/`]({BLOB}/envs). Versions below are those recorded in `results/machine.txt` at run time.\n\n")
        out += "| package | version | recorded |\n|---|---|---|\n"
        for k, (v, d) in sorted(self.versions().items(), key=lambda kv: kv[0].lower()):
            out += f"| {esc(k)} | `{esc(v[:90])}` | {esc(d[:10])} |\n"
        out += "\nThe relation of the author to each system is stated on the [conflict of interest](../conflict-of-interest/) page.\n"
        out += ("\n## Adapters\n\n`lib/adapters/<system>.jl` give the systems the same small interface "
                "(`OPS`, `EVAL`, `NTERMS`, `NFACTORS`, `UNSOLVED`, `VERSIONS`). Bench E has one task file per system, "
                "`E_suite/tasks_<system>.jl`, written the way that system's user would write it. An operation an adapter "
                "maps to `missing` is reported as *unavailable*.\n")
        return out

    def coi_summary(self):
        """One sentence from docs/disclosures.tsv: who declares a role in a system compared or in a source of problems."""
        by_c = {}
        for r in self.disclosures:
            if r["role"].lower() != "none" and (r["kind"] == "compared system" or r["kind"].startswith("source")):
                by_c.setdefault(r["contributor"], []).append(f"{r['role']} of {r['project']}" + (f" ({r['note']})" if r["note"] else ""))
        if not by_c:
            return "Conflict of interest: no contributor declares a relation to the systems compared or to the sources of the problems."
        ai = sorted({r["project"] for r in self.disclosures if r["kind"] == "AI assistance"})
        tail = f" AI assistance declared: {', '.join(esc(a) for a in ai)}." if ai else ""
        return "Conflict of interest: " + "; ".join(f"{esc(c)} is " + esc(", ".join(v[:-1]) + (" and " if len(v) > 1 else "") + v[-1]) for c, v in by_c.items()) + "." + tail

    def conflict_page(self):
        """The conflict of interest page, from docs/disclosures.tsv: every contributor's own declaration, the relation to
        every system present in the results, what limits the bias, how to add a declaration."""
        out = front("Conflict of interest", 4)
        out += (f"{self.coi_summary()}\n\n"
                "Every contributor to these benchmarks declares below their relation to the systems compared and to the "
                f"sources of the problems, in their own rows of [`docs/disclosures.tsv`]({BLOB}/docs/disclosures.tsv) "
                "(a row with no relation is also a declaration); a pull request that touches a task file, an adapter, a "
                f"check or a problem list comes with them ([CONTRIBUTING.md]({BLOB}/CONTRIBUTING.md)).\n\n")
        by_c = {}
        for r in self.disclosures:
            by_c.setdefault((r["contributor"], r["orcid"]), []).append(r)
        for (name, orcid), rows in by_c.items():
            head = f"{esc(name)} ([ORCID {esc(orcid)}](https://orcid.org/{esc(orcid)}))" if orcid else esc(name)
            out += f"## {head}\n\n| project | kind | role | note |\n|---|---|---|---|\n"
            for r in rows:
                if r["kind"] != "AI assistance":
                    out += f"| {esc(r['project'])} | {esc(r['kind'])} | {esc(r['role'])} | {esc(r['note'])} |\n"
            out += "\n"
        if not by_c:
            out += "*No declaration yet.*\n\n"
        out += ("## Use of AI assistants\n\n"
                "Each contributor declares the AI assistants they used, for what, and how the output was reviewed. This matters "
                "here more than elsewhere: an idiom an assistant generated for a system is a possible source of a benchmark-side "
                "error, which is why every case page shows the exact input sent to each system. The measurements themselves "
                "come from the scripts of the repository, never from an assistant.\n\n| contributor | assistant | used for | review and limits |\n|---|---|---|---|\n")
        ai = [r for r in self.disclosures if r["kind"] == "AI assistance"]
        for r in ai:
            out += f"| {esc(r['contributor'])} | {esc(r['project'])} | {esc(r['role'])} | {esc(r['note'])} |\n"
        if not ai:
            out += "| | none declared | | |\n"
        out += "\n"
        out += ("## Relation to every system of the results\n\n"
                "The systems are those present in the committed results files; *none declared* means that no contributor "
                "declares a relation.\n\n| system or package | kind | declared relations |\n|---|---|---|\n")
        for kind, names in self.packages_by_kind().items():
            for n in names:
                rel = [f"{r['contributor']}: {r['role']}" + (f" ({r['note']})" if r["note"] else "")
                       for r in self.disclosures if r["project"] == n and r["role"].lower() != "none"]
                out += f"| {esc(n)} | {'Julia package' if kind == 'julia' else 'other system'} | {esc('; '.join(rel)) if rel else 'none declared'} |\n"
        out += ("\n## What limits the bias\n\n"
                "- The inputs are fixed in the repository and every case page shows the exact text sent to each system "
                "next to its answer, so that a task that does not ask a system the way its users would can be seen.\n"
                "- Every answer is checked by a system-neutral test written in plain Julia (numeric evaluation at fixed "
                "points, canonical forms, reduction to zero), never by the system under test.\n"
                "- The task files of bench E were written by an external contributor (a fork of Giac.jl), and benches F, G "
                "and H take their problems from third parties (the 12000.org tests, the classical Gröbner systems, the "
                "OpenSymbolicRules rules; see the declarations above for who wrote them).\n"
                "- The raw data, the history of every run and the machine records are published under CC BY 4.0, and CI "
                "checks that the tables are what the scripts produce from the committed results.\n"
                "- Funding, employment or any other interest in a system compared is declared in the same file. The "
                "project is individual and non-commercial.\n\n"
                f"## Reporting\n\nAn idiom unfair to a system, or a check that favours one, is a bug: open an issue or a pull "
                f"request on the [repository]({REPO}) with the idiom that system's users would write.\n")
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
        out = front("History", 5)
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

    def data_files(self):
        """The raw files the site republishes: (relative path under static/data, source path)."""
        res = self.root / "results"
        files = [(p.name, p) for p in sorted(res.glob("*.tsv"))]
        for name in ("machine.txt", "environment.txt", "summary.md"):
            if (res / name).exists():
                files.append((name, res / name))
        for extra in ("F_integration/sample.tsv", "H_osr/rules.tsv", "G_groebner/inputs.jl", "I_scale/inputs.jl"):
            p = self.root / extra
            if p.exists():
                files.append((extra.replace("/", "_"), p))
        return files

    def write_data(self, static):
        """Copy the raw files under static/data and build data/results.zip; returns the file list with sizes."""
        d = static / "data"
        d.mkdir(parents=True, exist_ok=True)
        out = []
        for name, src in self.data_files():
            shutil.copyfile(src, d / name)
            out.append((name, src.stat().st_size))
        with zipfile.ZipFile(d / "results.zip", "w", zipfile.ZIP_DEFLATED) as z:
            for name, src in self.data_files():
                z.write(src, arcname=name)
        return out

    def data_page(self, files):
        out = front("Data", 3)
        out += (f'<p class="site-stamp">{self.stamp()}</p>\n\n'
                "Every number of this site comes from these files, republished as they are in the repository: one TSV per "
                "bench and system (columns `bench, system, idx, case, op, status, t_first_s, t_warm_s, result, note` and, in "
                "the runs from 2026-11-20, `input`; times in seconds, `result`, `note` and `input` truncated to 200, 300 and "
                "2 000 characters), the history of the runs, the "
                "machine and environment records, and the fixed inputs. Each bench page also offers its table as CSV, "
                "filtered and sorted as shown.\n\n"
                "- [results.zip](../data/results.zip): everything below in one archive.\n")
        for name, size in files:
            out += f"- [{esc(name)}](../data/{name}) ({size // 1024 + 1} kB)\n"
        out += ("\n## Reading them\n\n```python\nimport pandas as pd\n"
                "df = pd.read_csv('https://s-celles.github.io/computer-algebra-system-benchmarks/data/E_suite_giac.tsv', sep='\\t')\n"
                "df[df.status == 'verified'].t_warm_s.describe()\n```\n\n"
                "```julia\nusing CSV, DataFrames\n"
                "df = CSV.read(download(\"https://s-celles.github.io/computer-algebra-system-benchmarks/data/history.tsv\"), DataFrame)\n```\n")
        out += f"\nLicence of the data: CC BY 4.0 (cite the repository and the run date). Source files: [`results/`]({BLOB}/results).\n"
        return out

    def workflow(self):
        return front("Workflow", 6) + WORKFLOW.strip() + "\n"

    def methodology(self):
        parts = []
        for rel in ("docs/methodology.md", "docs/benches.md"):
            p = self.root / rel
            if not p.exists():
                continue
            body = re.sub(r"^# .*\n", "", p.read_text(encoding="utf-8"), count=1)
            body = re.sub(r"\]\((?!https?://|#)([^)]+)\)", lambda m: f"]({BLOB}/docs/{m.group(1)})", body)
            parts.append(f"From [`{rel}`]({BLOB}/{rel}).\n\n" + body)
        return front("Methodology", 7) + "\n\n---\n\n".join(parts)

    def llms(self):
        return (f"# Computer algebra system benchmarks\n\n> Reproducible, verified, dated benchmarks of computer algebra systems, {self.systems_sentence()}. {DISCLAIMER} {self.coi_summary()} Every contributor's declaration: {REPO.replace("github.com/s-celles/", "s-celles.github.io/")}/conflict-of-interest/\n\n- Consumes OpenSymbolicRules (OSR): {OSR}\n"
                + "\n".join(f"- {t}: {d}" for k, (t, d) in BENCHES.items() if k in self.results) + f"\n- Repository: {REPO}\n")


def read_citation(path):
    """The fields of CITATION.cff the site shows: title, authors [(given, family, orcid)], url, repository-code,
    licenses. A small reader of the flat layout of that file, so that the site has no second copy of its metadata."""
    out = {"title": "", "authors": [], "url": "", "repository-code": "", "license": []}
    if not path.exists():
        return out
    section, author = None, None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        key, _, val = line.strip().partition(":")
        val = val.strip().strip('"')
        if indent == 0:
            section, author = key, None
            if key in ("title", "url", "repository-code") and val:
                out[key] = val
            elif key == "license" and val:
                out["license"] = [val]
        elif section == "license" and line.strip().startswith("- "):
            out["license"].append(line.strip()[2:].strip())
        elif section == "authors":
            if line.strip().startswith("- "):
                author = {}
                out["authors"].append(author)
                key, _, val = line.strip()[2:].partition(":")
                val = val.strip().strip('"')
            if author is not None and key:
                author[key] = val
    return out


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def check_home(site, home):
    """Every number displayed on the home page against the data it claims to summarise; raises ValueError."""
    stat = lambda label: int(re.search(rf"<strong>(\d+)</strong><span>{re.escape(label)}</span>", home).group(1))
    ncb = site.ncases_by_bench()
    shown = {m.group(1): int(m.group(2)) for m in re.finditer(r"^\| \[([^\]]+)\]\(results/[^)]+\) \| (\d+) \|", home, re.M)}
    pk = site.packages_by_kind()
    problems = [
        (stat("cases") == sum(ncb.values()), f"cases tile {stat('cases')} != sum of benches {sum(ncb.values())}"),
        (sum(shown.values()) == stat("cases"), f"cases column sums to {sum(shown.values())}, tile says {stat('cases')}"),
        (len(shown) == len(site.results) == stat("benches"), "benches tile and table disagree with the results loaded"),
        (stat("Julia packages") == len(pk["julia"]) and stat("other systems") == len(pk["external"]),
         "package tiles disagree with the systems of the results"),
        (len(pk["julia"]) + len(pk["external"]) == len(site.packages()), "a system is counted in two kinds"),
        (all(n in home for n in pk["julia"] + pk["external"] if n != "SageMath"), "a system of the results is not named"),
    ]
    bad = [msg for ok, msg in problems if not ok]
    if bad:
        raise ValueError("home page inconsistent with the results: " + "; ".join(bad))


def generate(root, out):
    site = Site(root)
    c, s = pathlib.Path(out) / "content", pathlib.Path(out) / "static"
    home = site.home()
    check_home(site, home)
    write(c / "_index.md", home)
    write(c / "results" / "_index.md", site.results_index())
    for w, key in enumerate(site.results, 1):
        write(c / "results" / key.lower() / "_index.md", site.bench_page(key, w))
        for d, text in site.case_pages(key):
            write(c / "results" / key.lower() / d / "_index.md", text)
    write(c / "systems" / "_index.md", site.systems_page())
    write(c / "conflict-of-interest" / "_index.md", site.conflict_page())
    write(c / "environment" / "_index.md", site.environment_page())
    files = site.write_data(s)
    write(c / "data" / "_index.md", site.data_page(files))
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
