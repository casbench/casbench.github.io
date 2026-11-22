#!/usr/bin/env python3
"""Checks for the site generator. Run with python3 -I tools/site/test_sitegen.py."""
import csv
import math
import os
import pathlib
import re
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sitegen  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]

TSV = """bench\tsystem\tidx\tcase\top\tstatus\tt_first_s\tt_warm_s\tresult\tnote\tinput
D_coverage\tGiac.jl\t0\t_load\tusing\tverified\t4.1\tNaN\t\tpackage load time
D_coverage\tGiac.jl\t1\tfactor x^4-1\tfactor\tverified\t0.01\t0.0002\t(x-1)*(x+1)*(x^2+1)\t
D_coverage\tGiac.jl\t2\tztrans n\tztrans\twrong\t0.01\t0.0003\tz/(z-1)^2\t
D_coverage\tSymPy\t1\tfactor x^4-1\tfactor\tverified\t0.5\t0.004\t(x - 1)*(x + 1)*(x**2 + 1)\t\tfactor(x**4 - 1)
D_coverage\tSymPy\t2\tztrans n\tztrans\tunavailable\tNaN\tNaN\t\tno Z transform
D_coverage\tsympy\t3\tslow\tslow\ttimeout\tNaN\tNaN\t\tover the limit
D_coverage\tGiac.jl\t4\tslow\tslow\tverified\t0.2\t0.1\t1\ta second case with the same name
"""
MACHINE = """# 2026-11-18 08:28:32
host\tvm
cpu\tsome cpu x6
julia\t1.13.3
bench\tD_coverage
Giac.jl\t0.14.3
giac_version\t"giac 2.0.0"
"""


class SiteGenTests(unittest.TestCase):
    def make_root(self):
        d = pathlib.Path(tempfile.mkdtemp())
        (d / "results" / "testhost").mkdir(parents=True)
        (d / "results" / "REFERENCE").write_text("testhost\n", encoding="utf-8")
        (d / "results" / "testhost" / "D_coverage_giac.tsv").write_text(TSV, encoding="utf-8")
        (d / "results" / "testhost" / "machine.txt").write_text(MACHINE, encoding="utf-8")
        (d / "README.md").write_text("# Title\n", encoding="utf-8")
        (d / "CITATION.cff").write_text('cff-version: 1.2.0\ntitle: "A title"\ntype: software\nauthors:\n  - family-names: Doe\n'
                                        '    given-names: Jo\n    orcid: "https://orcid.org/0000-0000-0000-0001"\n'
                                        'repository-code: "https://example.org/repo"\nurl: "https://example.org/site"\n'
                                        'license:\n  - MIT\n  - CC-BY-4.0\n', encoding="utf-8")
        (d / "docs").mkdir()
        (d / "docs" / "methodology.md").write_text("# Methodology\n\nSee [../lib/common.jl](../lib/common.jl).\n", encoding="utf-8")
        (d / "docs" / "disclosures.tsv").write_text(
            "# declarations\ncontributor\torcid\tproject\tkind\trole\tnote\n"
            "Jo Doe\t0000-0000-0000-0001\tGiac.jl\tcompared system\tauthor and maintainer\tthe Julia package, not the engine\n"
            "Jo Doe\t0000-0000-0000-0001\tnone\tother\tnone\t\n"
            "Al Roe\t\tnone\tother\tnone\tno relation to any system compared\n"
            "Jo Doe\t0000-0000-0000-0001\tSome Assistant\tAI assistance\tused to draft the adapters\treviewed by the contributor\n", encoding="utf-8")
        return d

    def test_site_addresses_follow_canonical_and_preview_base(self):
        root = self.make_root()
        site = sitegen.Site(root, base_url="https://preview.example/branch")
        self.assertIn("https://preview.example/branch/results/", site.llms())
        self.assertIn("https://preview.example/branch/data/history.tsv", site.data_page([]))
        self.assertIn("https://github.com/casbench/casbench.github.io", site.llms())
        with patch.dict(os.environ, {"HUGO_BASEURL": "https://casbench.github.io/preview/"}):
            preview = sitegen.Site(root)
            self.assertIn("https://casbench.github.io/preview/results/", preview.llms())
        with patch.dict(os.environ, {"HUGO_BASEURL": ""}):
            canonical = sitegen.Site(root)
            self.assertIn("https://casbench.github.io/results/", canonical.llms())

    def test_committed_operation_metrics_match_site(self):
        table = ROOT / "tables" / "operation_metrics.tsv"
        if not table.exists():
            self.skipTest("operation metrics not present")
        with table.open(encoding="utf-8", newline="") as f:
            expected = {(r["bench"], r["source"], r["op"]): r for r in csv.DictReader(f, delimiter="\t")}
        site = sitegen.Site(ROOT)
        seen = set()
        for bench, systems in site.results.items():
            for system, rows in systems.items():
                source = f"{bench}_{site.system_key(bench, system)}.tsv"
                for op, group in site.operation_groups(bench, rows).items():
                    key = bench, source, op
                    self.assertIn(key, expected)
                    seen.add(key)
                    r = expected[key]
                    n, k, quartiles = sitegen.operation_metrics(group)
                    self.assertEqual((n, k), (int(r["attempted"]), int(r["solved"])), key)
                    if quartiles is None:
                        self.assertTrue(math.isnan(float(r["median_s"])), key)
                    else:
                        for value, column in zip(quartiles, ("q1_s", "median_s", "q3_s")):
                            self.assertTrue(math.isclose(value, float(r[column]), rel_tol=1e-12, abs_tol=1e-14), key)
        self.assertEqual(seen, set(expected))

    def test_operation_metrics(self):
        def row(status, warm, first=float("nan")):
            return {"status": status, "t_warm_s": warm, "t_first_s": first}
        rows = [row("verified", 1), row("verified", 3), row("verified", 9),
                row("timeout", 600), row("unavailable", 0)]
        self.assertEqual(sitegen.operation_metrics(rows), (4, 3, (2, 3, 6)))
        self.assertEqual(sitegen.operation_metrics([row("verified", 1), row("timeout", 600)]), (2, 1, (1, 1, 1)))
        self.assertIsNone(sitegen.operation_metrics([row("verified", 1), row("timeout", 600), row("wrong", 1)])[2])
        self.assertIsNone(sitegen.operation_metrics([row("verified", float("nan"))])[2])

    def test_integration_verification_is_separate(self):
        root = self.make_root()
        path = root / "results" / "testhost" / "F_integration_giac.tsv"
        command = "α = 1\n\tresult = \\frac{x}{2}\n```"
        encoded = command.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")
        path.write_text("bench\tsystem\tidx\tcase\top\tstatus\tt_first_s\tt_warm_s\tresult\tnote\tinput\tverify_status\tverify_time_s\tverify_input\n"
                        "F_integration\tGiac.jl\t1\tintegral\tintegrate_text\tverified_numeric\t1.0\t0.5\tx^2/2\tnumeric check\tintegrate(x,x)\tverified_symbolic\t4.2\t" + encoded + "\n", encoding="utf-8")
        out = pathlib.Path(tempfile.mkdtemp())
        sitegen.generate(root, out)
        synthesis = (out / "content" / "results" / "synthesis" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("1/1; 1 checked; median 4.20 s", synthesis)
        page = (out / "content" / "results" / "f_integration" / sitegen.slug(1, "integral") / "_index.md").read_text(encoding="utf-8")
        self.assertIn("verified_numeric", page)
        self.assertIn("verified_symbolic", page)
        self.assertIn("4.20 s", page)
        self.assertIn(command, page)
        self.assertIn("integrate(x,x)", page)

    def test_self_verification_median_requires_half(self):
        def row(status, time):
            return {"status": "verified_numeric", "verify_status": status, "verify_time_s": time}
        rows = [row("verified_symbolic", 1.0), row("verify_unsolved", 2.0), row("verify_timeout", 60.0)]
        summary = sitegen.self_verification_summary(rows)
        self.assertIn("1/3; 3 checked", summary)
        self.assertIn("median omitted", summary)

    def test_numeric_identity_case_displays_evaluation(self):
        root = self.make_root()
        path = root / "results" / "testhost" / "D_coverage_giac.tsv"
        with path.open("a", encoding="utf-8") as f:
            f.write("D_coverage\tGiac.jl\t5\tidentity test\tsimplify\tverified_numeric\t0.01\t0.001\t0\t80-digit evaluation=0.0\tsimplify(lhs-rhs)\n")
        out = pathlib.Path(tempfile.mkdtemp())
        sitegen.generate(root, out)
        page = (out / "content" / "results" / "d_coverage" / sitegen.slug(5, "identity test") / "_index.md").read_text(encoding="utf-8")
        self.assertIn("simplify(lhs-rhs)", page)
        self.assertIn("80-digit evaluation=0.0", page)
        self.assertIn("data-status=\"verified_numeric\"", page)
        self.assertLess(page.index("#### Input"), page.index("#### Output"))

    def test_pages(self):
        root = self.make_root()
        out = pathlib.Path(tempfile.mkdtemp())
        site = sitegen.generate(root, out)
        self.assertEqual(site.ncases(), 4)                      # _load rows are dropped; cases 3 and 4 share a name
        self.assertEqual(site.ncases_by_bench(), {"D_coverage": 4})
        self.assertEqual(site.systems(), ["Giac.jl", "SymPy"])   # the supervisor key sympy is relabelled
        self.assertEqual(site.packages(), ["Giac.jl", "SymPy"])
        self.assertEqual(site.packages_by_kind(), {"julia": ["Giac.jl"], "external": ["SymPy"]})
        synthesis = (out / "content" / "results" / "synthesis" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("Giac.jl", synthesis)
        self.assertIn("2/3 verified", synthesis)
        self.assertNotIn("warm time, sum", synthesis)
        self.assertIn("weight: 1", synthesis)
        page = (out / "content" / "results" / "d_coverage" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("## Operation metrics", page)
        self.assertIn("not shown: fewer than half solved or missing time", page)
        self.assertIn('<span class="sk-badge sk-tone--good" data-status="verified"', page)          # site-kit badges
        self.assertIn('<span class="sk-badge sk-tone--neutral-dashed" data-status="unavailable"', page)
        self.assertIn("200 µs", page)                            # warm time formatted
        self.assertIn("4.0 ms", page)
        self.assertIn("[factor x^4-1](001-factor-x-4-1/)", page)  # each case links to its page
        self.assertIn('class="chart dotplot"', page)                 # the dot plot of the bench
        self.assertIn('fill="none"', page)                           # a hollow mark for the wrong answer
        home = (out / "content" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("<strong>4</strong><span>cases</span>", home)
        self.assertEqual(home.count('class="sk-stat"'), 4)                          # site-kit: at most four tiles
        self.assertIn('<p class="data-stamp">Data from the run of 2026-11-18 on the host <code>testhost</code>', home)
        self.assertNotIn("Site generated", home)                                    # no build time: builds are identical
        self.assertIn('<div class="disclaimer">\n\n**Disclaimer.**', home)
        self.assertIn("**Provenance.** An AI assistant wrote", home)
        self.assertIn("non-commercial", home)
        self.assertLess(home.index("data-stamp"), home.index('class="disclaimer"'))   # the order of site-kit SPEC section 3
        self.assertLess(home.index('class="disclaimer"'), home.index('class="sk-stats"'))
        self.assertIn("## Sources", home)
        self.assertIn("**Not reproduced here.**", home)
        self.assertIn("| [D. Functional coverage](results/d_coverage/) | 4 | 2 |", home)   # cases and systems per bench
        self.assertIn("| E. Problem suite | no run committed yet |", home)               # a bench without results is listed
        self.assertIn("<strong>2</strong><span>systems: 1 Julia package, 1 other</span>", home)
        self.assertIn("Julia packages (Giac.jl) and other systems (SymPy)", home)   # the lists come from the results
        self.assertIn("## Cite", home)                                               # site-kit SK-HOME-CITE
        self.assertIn("[Disclosures](./disclosures/)", home)                        # SK-HOME-DISCLOSURE: the href ends in /disclosures/
        self.assertIn("Disclosure: Jo Doe is author and maintainer of Giac.jl (the Julia package, not the engine). AI assistance declared: Some Assistant.", home)
        coi = (out / "content" / "disclosures" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("aliases: ['/conflict-of-interest/']", coi)                   # the 0.3 address redirects
        self.assertIn("## Jo Doe ([ORCID 0000-0000-0000-0001](https://orcid.org/0000-0000-0000-0001))", coi)
        self.assertIn("## Al Roe\n", coi)                                              # a declaration of no relation
        self.assertIn("| none | other | none | no relation to any system compared |", coi)
        self.assertIn("## Use of AI assistants", coi)
        self.assertIn("| Jo Doe | Some Assistant | used to draft the adapters | reviewed by the contributor |", coi)
        self.assertIn("Jo Doe ([ORCID 0000-0000-0000-0001](https://orcid.org/0000-0000-0000-0001))", home)
        self.assertIn("@misc{doe2026casbench,", home)
        self.assertIn("run of 2026-11-18", home)
        self.assertIn("MIT, CC-BY-4.0", home)
        sysp = (out / "content" / "docs" / "systems" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("| Giac.jl | `0.14.3` | 2026-11-18 |", sysp)
        self.assertIn("| system or source | kind | Jo Doe | Al Roe |", coi)                       # systems x contributors
        self.assertIn("| Giac.jl | Julia package | author and maintainer (the Julia package, not the engine) | none |", coi)
        self.assertIn("| SymPy | other system | none | none |", coi)
        self.assertIn("disclosures/", sysp)
        meth = (out / "content" / "methodology" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("## Pipeline", meth)                                            # site-kit SPEC section 8
        self.assertIn("## What a result means", meth)
        self.assertIn("## Checks of the expected values", meth)
        self.assertIn("## Metrics", meth)
        self.assertIn("separate process", meth)
        self.assertIn("simplify(diff(F, x) - f) == 0", meth)
        self.assertIn("aliases: ['/workflow/']", meth)
        stp = (out / "content" / "docs" / "statuses" / "_index.md").read_text(encoding="utf-8")
        for planned in ("verified_numeric", "verified_symbolic", "verify_timeout", "verify_unsolved"):
            self.assertIn(planned, stp)
        for st in sitegen.STATUSES:
            self.assertIn(f'data-status="{st}"', stp)                                  # every word of a badge is defined
        self.assertTrue((out / "static" / "llms-full.txt").exists())
        full = (out / "static" / "llms-full.txt").read_text(encoding="utf-8")
        self.assertIn("- 1. factor x^4-1 [factor]: Giac.jl verified 200 µs; SymPy verified 4.0 ms", full)
        self.assertIn(sitegen.BLOB + "/docs/../lib/common.jl", meth)   # relative links rewritten from docs/
        self.assertTrue((out / "static" / "llms.txt").exists())
        self.assertTrue((out / "static" / "data" / "testhost" / "D_coverage_giac.tsv").exists())   # raw data republished, per host
        self.assertTrue((out / "static" / "data" / "results.zip").exists())
        data = (out / "content" / "docs" / "data" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("testhost/D_coverage_giac.tsv", data)
        self.assertIn("data/testhost/D_coverage_giac.tsv", page)                     # linked from the bench page
        self.assertIn("come from the host `testhost`", home)
        envp = (out / "content" / "docs" / "environment" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("## testhost (reference)", envp)

    def test_case_pages(self):
        root = self.make_root()
        out = pathlib.Path(tempfile.mkdtemp())
        sitegen.generate(root, out)
        case = out / "content" / "results" / "d_coverage" / "001-factor-x-4-1" / "_index.md"
        self.assertTrue(case.exists(), "one page per case")
        text = case.read_text(encoding="utf-8")
        self.assertIn("sidebar:\n  exclude: true\nexcludeSearch: true\n---", text)   # case pages stay out of the sidebar
        self.assertIn("(x-1)*(x+1)*(x^2+1)", text)                 # every system's full answer
        self.assertIn("(x - 1)*(x + 1)*(x**2 + 1)", text)
        self.assertIn("| Giac.jl | <span", text)
        self.assertIn("factor(x**4 - 1)", text)                      # the input sent to SymPy
        self.assertIn("Not recorded in this run", text)              # the Giac row of the fixture has no input
        self.assertIn("#### Output", text)
        self.assertIn("$$\\operatorname{factor}\\left(x^{4} - 1\\right)$$", text)   # the statement rendered as LaTeX
        self.assertTrue((out / "content" / "results" / "d_coverage" / "003-slow" / "_index.md").exists())
        self.assertTrue((out / "content" / "results" / "d_coverage" / "004-slow" / "_index.md").exists())

    def test_history(self):
        root = self.make_root()
        (root / "results" / "history.tsv").write_text(
            "date\thost\tbench\tsystem\tn\tverified\twrong\tunverified\tunsolved\tunavailable\terror\ttimeout\tt_warm_sum\tt_warm_median\tversions\tsource\n"
            "2026-11-18 08:28:32\ttesthost\tD_coverage\tgiac\t23\t22\t0\t1\t0\t0\t0\t0\t1.8\t7.5e-05\t\tabc\n"
            "2026-11-19 10:00:00\ttesthost\tD_coverage\tgiac\t23\t23\t0\t0\t0\t0\t0\t0\t1.8\t7.0e-05\t\trun\n", encoding="utf-8")
        out = pathlib.Path(tempfile.mkdtemp())
        site = sitegen.generate(root, out)
        self.assertEqual(len(site.history), 2)
        page = (out / "content" / "history" / "_index.md").read_text(encoding="utf-8")
        self.assertEqual(page.count('<svg class="viz-chart"'), 1)                 # verified counts only
        self.assertIn('<g class="viz-pt" aria-label="2026-11-18 08:28: Giac.jl 22">', page)   # the label starts with the date
        self.assertIn('data-viz="dense"', page)
        self.assertIn("<table", page.replace("| date | host |", "<table"))             # the values are on the page
        one = sitegen.viz_chart({"a": [("2026-11-18", 1.0), ("2026-11-19", 2.0)]}, "t", "y")
        self.assertIn('<svg class="viz-chart"', one)
        self.assertIn('aria-label="t"', one)
        many = sitegen.viz_chart({k: [("2026-11-18", 1.0), ("2026-11-19", 2.0)] for k in "abc"}, "t", "y")
        self.assertIn('class="viz-multiples"', many)                                   # more than two series: small multiples
        self.assertEqual(many.count('<svg class="viz-chart"'), 3)
        self.assertIn("no data yet", sitegen.viz_chart({"a": []}, "t", "y"))

    def test_hosts(self):
        """A second host gets its own directory, the Hosts page compares it with the reference, the home page names it."""
        root = self.make_root()
        (root / "results" / "other").mkdir()
        (root / "results" / "other" / "D_coverage_giac.tsv").write_text(TSV.replace("\t0.2\t0.1\t", "\t0.2\t0.2\t"), encoding="utf-8")
        (root / "results" / "other" / "machine.txt").write_text(MACHINE.replace("host\tvm", "host\tlaptop"), encoding="utf-8")
        out = pathlib.Path(tempfile.mkdtemp())
        site = sitegen.generate(root, out)
        self.assertEqual(sorted(site.hosts), ["other", "testhost"])
        self.assertEqual(site.reference, "testhost")
        self.assertEqual(site.ncases(), 4)                                             # the tiles count the reference host only
        hosts = (out / "content" / "docs" / "hosts" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("| bench | system | `testhost` | `other` |", hosts)
        self.assertIn("| D. Functional coverage | Giac.jl | 2/3 verified | 2/3 verified |", hosts)
        home = (out / "content" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("1 other host (`other`) ran the same benches", home)
        self.assertTrue((out / "static" / "data" / "other" / "D_coverage_giac.tsv").exists())

    def test_workflow(self):
        """The pipeline diagrams are on the Methodology page, with no ; < or # in their labels (site-kit SK-MERMAID)."""
        root = self.make_root()
        out = pathlib.Path(tempfile.mkdtemp())
        sitegen.generate(root, out)
        wf = (out / "content" / "methodology" / "_index.md").read_text(encoding="utf-8")
        self.assertEqual(wf.count("```mermaid"), 4)
        self.assertIn("sequenceDiagram", wf)
        for block in re.findall(r"```mermaid\n(.*?)```", wf, re.S):
            for line in block.splitlines()[1:]:
                labels = [next(g for g in m.groups() if g is not None)
                          for m in re.finditer(r"\[([^\]]*)\]|\(([^)]*)\)|\{([^}]*)\}|\|([^|]*)\|", line)]
                m = re.match(r"^\s*[^\s:]+\s*-{1,2}>>?\s*[^:]+:(.*)$", line)
                labels += [m.group(1)] if m else []
                for lab in labels:
                    self.assertIsNone(re.search(r"[;<#]", lab), lab)

    def test_brand(self):
        """The hero banner is on the home page, and the committed copies under site/static are the generated ones."""
        root = self.make_root()
        out = pathlib.Path(tempfile.mkdtemp())
        sitegen.generate(root, out)
        home = (out / "content" / "_index.md").read_text(encoding="utf-8")
        self.assertIn('<p class="site-banner"><img src="brand/casbench-banner.svg"', home)
        self.assertLess(home.index("site-banner"), home.index("project-kicker"))    # banner, kicker, statement, then the stamp
        self.assertLess(home.index("project-kicker"), home.index("data-stamp"))
        for name in ("casbench-banner.svg", "casbench-mark.svg"):
            a, b = ROOT / "assets" / "brand" / name, ROOT / "site" / "static" / "brand" / name
            self.assertTrue(a.exists() and b.exists(), name)
            self.assertEqual(a.read_text(encoding="utf-8"), b.read_text(encoding="utf-8"), f"{name}: regenerate and copy")
        banner = (ROOT / "assets" / "brand" / "casbench-banner.svg").read_text(encoding="utf-8")
        self.assertNotIn("\u2014", banner)                                        # no em-dash in site text

    def test_read_citation(self):
        c = sitegen.read_citation(ROOT / "CITATION.cff")
        self.assertEqual([a["family-names"] for a in c["authors"]], ["Celles"])
        self.assertEqual(c["authors"][0]["orcid"], "https://orcid.org/0000-0001-9987-4338")
        self.assertEqual(c["license"], ["MIT", "CC-BY-4.0"])
        self.assertEqual(c["repository-code"], sitegen.REPO)
        footer = (ROOT / "site" / "layouts" / "_partials" / "custom" / "footer.html").read_text(encoding="utf-8")
        self.assertIn(c["authors"][0]["orcid"], footer)            # the footer names the author of CITATION.cff
        self.assertIn(c["repository-code"], footer)

    def test_package(self):
        self.assertEqual(sitegen.package("Primes.jl factor"), ("julia", "Primes.jl"))
        self.assertEqual(sitegen.package("Giac.jl ifactor"), ("julia", "Giac.jl"))
        self.assertEqual(sitegen.package("msolve (AlgebraicSolving.jl)"), ("external", "msolve"))
        self.assertEqual(sitegen.package("Sage/Maxima"), ("external", "SageMath"))
        self.assertEqual(sitegen.package("Compute Engine"), ("external", "Compute Engine"))
        self.assertEqual(sitegen.package("SymPy"), ("external", "SymPy"))

    def test_fmt_time(self):
        self.assertEqual(sitegen.fmt_time(2.5e-6), "2 µs")
        self.assertEqual(sitegen.fmt_time(0.0123), "12.3 ms")
        self.assertEqual(sitegen.fmt_time(3.0), "3.00 s")
        self.assertEqual(sitegen.fmt_time(float("nan")), "")

    def test_slug(self):
        self.assertEqual(sitegen.slug(7, "Serret's integral"), "007-serret-s-integral")
        self.assertEqual(sitegen.slug(12, "∫ x²"), "012-x")

    def test_real_repository(self):
        if not (ROOT / "results").exists():
            self.skipTest("no results directory")
        out = pathlib.Path(tempfile.mkdtemp())
        site = sitegen.generate(ROOT, out)
        self.assertGreaterEqual(len(site.results), 1)
        if "E_suite" in site.results:
            self.assertGreaterEqual(len(site.categories), 100)

    def test_home_numbers_match_results(self):
        """Every number displayed on the home page, recomputed here from results/*.tsv without the generator's
        own counting: total of cases = sum of cases per bench (an index of a bench is one case), the systems are
        the distinct system columns of the results files."""
        if not (ROOT / "results").exists():
            self.skipTest("no results directory")
        cases, systems = {}, set()
        reference = (ROOT / "results" / "REFERENCE").read_text(encoding="utf-8").strip()
        for p in sorted((ROOT / "results" / reference).glob("*_*.tsv")):
            with open(p, newline="", encoding="utf-8") as f:
                for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
                    if r.get("case") == "_load" or not r.get("idx", "").isdigit():
                        continue
                    cases.setdefault(r["bench"], set()).add(int(r["idx"]))
                    systems.add(sitegen.SYSTEM_LABELS.get(r["system"], r["system"]))
        out = pathlib.Path(tempfile.mkdtemp())
        site = sitegen.generate(ROOT, out)
        home = (out / "content" / "_index.md").read_text(encoding="utf-8")
        tile = lambda label: int(re.search(rf"<strong>(\d+)</strong><span>{label}</span>", home).group(1))
        self.assertEqual(tile("cases"), sum(len(v) for v in cases.values()))
        self.assertEqual(tile("benches"), len(cases))
        column = {m.group(1): int(m.group(2)) for m in re.finditer(r"^\| \[[A-Z]\. [^\]]+\]\(results/([a-z_]+)/\) \| (\d+) \|", home, re.M)}
        self.assertEqual(column, {b.lower(): len(v) for b, v in cases.items()})
        self.assertEqual(sorted(systems), site.systems())
        kinds = {}
        for label in systems:
            kind, name = sitegen.package(label)
            kinds.setdefault(kind, set()).add(name)
        m = re.search(r"<strong>(\d+)</strong><span>systems: (\d+) Julia packages?, (\d+) others?</span>", home)
        self.assertIsNotNone(m)
        self.assertEqual(int(m.group(2)), len(kinds.get("julia", ())))
        self.assertEqual(int(m.group(3)), len(kinds.get("external", ())))
        self.assertEqual(int(m.group(1)), len(kinds.get("julia", ())) + len(kinds.get("external", ())))
        for name in {n for v in kinds.values() for n in v}:
            self.assertIn(name, home, f"{name} is in the results but not named on the home page")

    def test_disclosures_file(self):
        """docs/disclosures.tsv parses, has the expected columns and every row a kind of the documented vocabulary."""
        rows = sitegen.read_disclosures(ROOT / "docs" / "disclosures.tsv")
        self.assertTrue(rows)
        for r in rows:
            self.assertEqual(set(r), {"contributor", "orcid", "project", "kind", "role", "note"})
            self.assertTrue(r["kind"] in ("compared system", "benchmark", "AI assistance", "other") or r["kind"].startswith("source of bench "), r)
        self.assertTrue(any(r["kind"] == "AI assistance" for r in rows), "the use of AI assistants is declared")
        agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        self.assertIn("docs/disclosures.tsv", agents)                 # the instructions for agents ask for the declaration
        footer = (ROOT / "site" / "layouts" / "_partials" / "custom" / "footer.html").read_text(encoding="utf-8")
        self.assertIn("/disclosures/", footer)

    def test_check_home_rejects_wrong_numbers(self):
        root = self.make_root()
        out = pathlib.Path(tempfile.mkdtemp())
        site = sitegen.generate(root, out)
        home = site.home()
        sitegen.check_home(site, home)                                                 # the generated page passes
        with self.assertRaises(ValueError):
            sitegen.check_home(site, home.replace("<strong>4</strong><span>cases</span>", "<strong>5</strong><span>cases</span>"))
        with self.assertRaises(ValueError):
            sitegen.check_home(site, home.replace("systems: 1 Julia package, 1 other", "systems: 1 Julia package, 2 others"))
        with self.assertRaises(ValueError):                                            # a fifth tile
            sitegen.check_home(site, home.replace('</div>\n\n[Results]', '<a class="sk-stat" href="x"><strong>1</strong><span>x</span></a>\n</div>\n\n[Results]'))

    def test_rur_page_and_synthesis_use_committed_rows(self):
        root = self.make_root()
        host = root / "results" / "testhost"
        header = "bench\tsystem\tidx\tcase\top\tstatus\tt_first_s\tt_warm_s\tresult\tnote\tinput\n"
        (host / "J_rur_msolve.tsv").write_text(header +
            "J_rur\tmsolve (AlgebraicSolving.jl)\t1\tkatsura5 over Q\trur\tverified_numeric\t1\t0.5\tRUR output\treal solutions checked\tpolynomial input\n", encoding="utf-8")
        site = sitegen.Site(root)
        self.assertIn("J_rur", site.results)
        self.assertIn("1/1 verified", site.synthesis_page())
        self.assertTrue(any("RUR output" in text and "polynomial input" in text for _, text in site.case_pages("J_rur")))

    def test_hard_tier_keeps_its_own_operation_and_budget(self):
        root = self.make_root()
        host = root / "results" / "testhost"
        header = "bench\tsystem\tidx\tcase\top\tstatus\tt_first_s\tt_warm_s\tresult\tnote\tinput\n"
        (host / "G_groebner_giac.tsv").write_text(header +
            "G_groebner\tGiac.jl\t1\tbase\tgroebner\tverified\t1\t0.5\tbasis\tbase\tbase input\n", encoding="utf-8")
        (host / "G_groebner_hard_giac.tsv").write_text(header +
            "G_groebner\tGiac.jl\t33\tcyclic8 over Q (hard tier)\tgroebner_hard\tverified\t2\t1\tbasis\thard tier; per-case budget 600 s\thard input\n", encoding="utf-8")
        site = sitegen.Site(root)
        rows = site.results["G_groebner"]["Giac.jl"]
        self.assertEqual(set(site.operation_groups("G_groebner", rows)), {"groebner", "groebner_hard"})
        self.assertIn("G_groebner_hard_giac.tsv", site.bench_page("G_groebner", 3))
        cases = dict(site.case_pages("G_groebner"))
        self.assertTrue(any("per-case budget 600 s" in text and "hard input" in text for text in cases.values()))

    def test_bench_e_statements_follow_problems(self):
        """E_suite/statements.tsv has one row per problem of E_suite/problems.jl, in the same order and with the same
        name, since the pages look a statement up by position (two problems share a name)."""
        probs, stm = ROOT / "E_suite" / "problems.jl", ROOT / "E_suite" / "statements.tsv"
        if not (probs.exists() and stm.exists()):
            self.skipTest("no bench E")
        names = re.findall(r'^\s+P\(CAT\[\d+\], "((?:[^"\\]|\\.)*)"', probs.read_text(encoding="utf-8"), re.M)
        rows = [l.split("\t")[0] for l in stm.read_text(encoding="utf-8").splitlines()
                if l and not l.startswith("#") and not l.startswith("name\t")]
        self.assertEqual(rows, names)
        # Historical identifiers must still refer to the same case after additions.
        ref = (ROOT / "results" / "REFERENCE").read_text(encoding="utf-8").strip()
        for file in (ROOT / "results" / ref).glob("E_suite_*.tsv"):
            for row in sitegen.read_tsv(file):
                if row["idx"] > 0:
                    self.assertEqual(names[row["idx"] - 1], row["case"], (file.name, row["idx"]))


if __name__ == "__main__":
    unittest.main()
