#!/usr/bin/env python3
"""Checks for the site generator. Run with python3 -I tools/site/test_sitegen.py."""
import pathlib
import sys
import tempfile
import unittest

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
        (d / "results").mkdir()
        (d / "results" / "D_coverage_giac.tsv").write_text(TSV, encoding="utf-8")
        (d / "results" / "machine.txt").write_text(MACHINE, encoding="utf-8")
        (d / "README.md").write_text("# Title\n", encoding="utf-8")
        (d / "docs").mkdir()
        (d / "docs" / "methodology.md").write_text("# Methodology\n\nSee [../lib/common.jl](../lib/common.jl).\n", encoding="utf-8")
        return d

    def test_pages(self):
        root = self.make_root()
        out = pathlib.Path(tempfile.mkdtemp())
        site = sitegen.generate(root, out)
        self.assertEqual(site.ncases(), 3)                      # _load rows are dropped
        self.assertEqual(site.systems(), ["Giac.jl", "SymPy"])   # the supervisor key sympy is relabelled
        self.assertEqual(site.packages(), ["Giac.jl", "SymPy"])
        page = (out / "content" / "results" / "d_coverage" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("verdict--verified", page)
        self.assertIn("verdict--unavailable", page)
        self.assertIn("200 µs", page)                            # warm time formatted
        self.assertIn("4.0 ms", page)
        self.assertIn("[factor x^4-1](001-factor-x-4-1/)", page)  # each case links to its page
        self.assertIn('class="chart dotplot"', page)                 # the dot plot of the bench
        self.assertIn('fill="none"', page)                           # a hollow mark for the wrong answer
        home = (out / "content" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("<strong>3</strong><span>cases</span>", home)
        self.assertIn("<strong>2</strong><span>packages</span>", home)
        sysp = (out / "content" / "systems" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("| Giac.jl | `0.14.3` | 2026-11-18 |", sysp)
        meth = (out / "content" / "methodology" / "_index.md").read_text(encoding="utf-8")
        self.assertIn(sitegen.BLOB + "/docs/../lib/common.jl", meth)   # relative links rewritten from docs/
        self.assertTrue((out / "static" / "llms.txt").exists())
        self.assertTrue((out / "static" / "data" / "D_coverage_giac.tsv").exists())   # raw data republished
        self.assertTrue((out / "static" / "data" / "results.zip").exists())
        data = (out / "content" / "data" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("D_coverage_giac.tsv", data)
        self.assertIn("data/D_coverage_giac.tsv", page)                              # linked from the bench page

    def test_case_pages(self):
        root = self.make_root()
        out = pathlib.Path(tempfile.mkdtemp())
        sitegen.generate(root, out)
        case = out / "content" / "results" / "d_coverage" / "001-factor-x-4-1" / "_index.md"
        self.assertTrue(case.exists(), "one page per case")
        text = case.read_text(encoding="utf-8")
        self.assertIn("(x-1)*(x+1)*(x^2+1)", text)                 # every system's full answer
        self.assertIn("(x - 1)*(x + 1)*(x**2 + 1)", text)
        self.assertIn("| Giac.jl | <span", text)
        self.assertIn("factor(x**4 - 1)", text)                      # the input sent to SymPy
        self.assertIn("Not recorded in this run", text)              # the Giac row of the fixture has no input
        self.assertIn("#### Output", text)
        self.assertIn("$$\\operatorname{factor}\\left(x^{4} - 1\\right)$$", text)   # the statement rendered as LaTeX
        self.assertTrue((out / "content" / "results" / "d_coverage" / "003-slow" / "_index.md").exists())

    def test_history(self):
        root = self.make_root()
        (root / "results" / "history.tsv").write_text(
            "date\tbench\tsystem\tn\tverified\twrong\tunverified\tunsolved\tunavailable\terror\ttimeout\tt_warm_sum\tt_warm_median\tversions\tsource\n"
            "2026-11-18 08:28:32\tD_coverage\tgiac\t23\t22\t0\t1\t0\t0\t0\t0\t1.8\t7.5e-05\t\tabc\n"
            "2026-11-19 10:00:00\tD_coverage\tgiac\t23\t23\t0\t0\t0\t0\t0\t0\t1.8\t7.0e-05\t\trun\n", encoding="utf-8")
        out = pathlib.Path(tempfile.mkdtemp())
        site = sitegen.generate(root, out)
        self.assertEqual(len(site.history), 2)
        page = (out / "content" / "history" / "_index.md").read_text(encoding="utf-8")
        self.assertEqual(page.count("<svg"), 2)                  # verified and median time charts
        self.assertIn("Site generated", page)
        home = (out / "content" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("last run recorded 2026-11-18 08:28:32", home)
        self.assertIn('<svg class="chart"', sitegen.svg_chart({"a": [("2026-11-18", 1.0), ("2026-11-19", 2.0)]}, "t", "y"))
        self.assertIn("no data yet", sitegen.svg_chart({"a": []}, "t", "y"))

    def test_workflow(self):
        root = self.make_root()
        out = pathlib.Path(tempfile.mkdtemp())
        sitegen.generate(root, out)
        wf = (out / "content" / "workflow" / "_index.md").read_text(encoding="utf-8")
        self.assertEqual(wf.count("```mermaid"), 4)
        self.assertIn("sequenceDiagram", wf)

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


if __name__ == "__main__":
    unittest.main()
