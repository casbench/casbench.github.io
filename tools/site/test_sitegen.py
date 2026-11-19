#!/usr/bin/env python3
"""Checks for the site generator. Run with python3 -I tools/site/test_sitegen.py."""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sitegen  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]

TSV = """bench\tsystem\tidx\tcase\top\tstatus\tt_first_s\tt_warm_s\tresult\tnote
D_coverage\tGiac.jl\t0\t_load\tusing\tverified\t4.1\tNaN\t\tpackage load time
D_coverage\tGiac.jl\t1\tfactor x^4-1\tfactor\tverified\t0.01\t0.0002\t(x-1)*(x+1)*(x^2+1)\t
D_coverage\tGiac.jl\t2\tztrans n\tztrans\twrong\t0.01\t0.0003\tz/(z-1)^2\t
D_coverage\tSymPy\t1\tfactor x^4-1\tfactor\tverified\t0.5\t0.004\t(x - 1)*(x + 1)*(x**2 + 1)\t
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
        (d / "README.md").write_text("# Title\n\nSee [lib/common.jl](lib/common.jl).\n", encoding="utf-8")
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
        home = (out / "content" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("<strong>3</strong><span>cases</span>", home)
        self.assertIn("<strong>2</strong><span>packages</span>", home)
        sysp = (out / "content" / "systems" / "_index.md").read_text(encoding="utf-8")
        self.assertIn("| Giac.jl | `0.14.3` | 2026-11-18 |", sysp)
        meth = (out / "content" / "methodology" / "_index.md").read_text(encoding="utf-8")
        self.assertIn(sitegen.BLOB + "/lib/common.jl", meth)      # relative links rewritten
        self.assertTrue((out / "static" / "llms.txt").exists())

    def test_fmt_time(self):
        self.assertEqual(sitegen.fmt_time(2.5e-6), "2 µs")
        self.assertEqual(sitegen.fmt_time(0.0123), "12.3 ms")
        self.assertEqual(sitegen.fmt_time(3.0), "3.00 s")
        self.assertEqual(sitegen.fmt_time(float("nan")), "")

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
