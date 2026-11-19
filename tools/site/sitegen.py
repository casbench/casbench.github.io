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
import html
import math
import pathlib
import re

REPO = "https://github.com/s-celles/computer_algebra_system_benchmarks"
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
}
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
                 "msolve": "msolve (AlgebraicSolving.jl)", "maxima": "Maxima", "fricas": "FriCAS", "reduce": "Reduce"}
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
    participant N as nix run .#bench
    participant J as julia (one process per bench and system)
    U->>N: git clone --recurse-submodules; nix run .#bench
    N->>N: pin julia 1.13.3, python3+sympy, record environment.txt
    N->>J: run_all.jl: supervise(env, worker, bench, system, out, timeout)
    J-->>N: results/<bench>_<system>.tsv
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
        out += ("Benchmarks of computer algebra systems reachable from Julia: Giac.jl, Symbolics.jl, SymPy (through "
                "SymPyPythonCall.jl), SymJ.jl, Primes.jl and LibPARI.jl. Every number comes from a script in the "
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
        out += "\n## Status vocabulary\n\n| status | meaning |\n|---|---|\n"
        for s in STATUSES:
            out += f"| {badge(s)} | {STATUS_HELP[s]} |\n"
        out += (f"\n[Workflow](workflow/) · [Methodology](methodology/) · [Systems and versions](systems/) · "
                f"[Machine](environment/) · [Repository]({REPO})\n")
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

    def workflow(self):
        return front("Workflow", 4) + WORKFLOW.strip() + "\n"

    def methodology(self):
        readme = (self.root / "README.md").read_text(encoding="utf-8")
        body = re.sub(r"^# .*\n", "", readme, count=1)
        body = re.sub(r"\]\((?!https?://|#)([^)]+)\)", lambda m: f"]({BLOB}/{m.group(1)})", body)
        return front("Methodology", 5) + f"From [`README.md`]({BLOB}/README.md).\n\n" + body

    def llms(self):
        return (f"# Computer algebra system benchmarks\n\n> Reproducible, verified, dated benchmarks of CAS reachable from Julia. {DISCLAIMER}\n\n"
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
