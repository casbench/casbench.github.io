#!/usr/bin/env python3
"""Checks for tools/g_hard_summary.py. Run with python3 -I tools/test_g_hard_summary.py."""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import g_hard_summary  # noqa: E402

HEADER = ("bench\tsystem\tidx\tcase\top\tstatus\tt_first_s\tt_warm_s\tresult\tnote\tinput\tt_wall_s\tt_repeats_s\tload_avg"
          "\trun\tverify_status\tverify_time_s\tverify_input\n")
ROW = ("G_groebner\tGiac.jl\t33\tcyclic8 over Q\tgroebner_hard\tverified\t12.5\tNaN\t[x^2-1, y]\tk=1372 sha=abc123; check_wall_s=4.1"
       "\tgbasis([...])\t12.5\t12.5\t2.1\t20261128_host2_ghard_fad4bc5\t\tNaN\t\n")


class Summary(unittest.TestCase):
    def test_keeps_everything_but_the_answer_and_the_input(self):
        text = g_hard_summary.summary_text(HEADER + ROW)
        header, row = text.splitlines()
        self.assertEqual(header + "\n", HEADER)
        cols = dict(zip(HEADER.rstrip("\n").split("\t"), row.split("\t")))
        self.assertEqual(cols["result"], "")
        self.assertEqual(cols["input"], "")
        self.assertEqual(cols["status"], "verified")
        self.assertEqual(cols["note"], "k=1372 sha=abc123; check_wall_s=4.1")
        self.assertEqual(cols["t_first_s"], "12.5")
        self.assertEqual(cols["run"], "20261128_host2_ghard_fad4bc5")

    def test_writes_the_summary_and_the_checksum_of_the_full_file(self):
        d = pathlib.Path(tempfile.mkdtemp())
        (d / "G_groebner_hard_giac.tsv").write_text(HEADER + ROW, encoding="utf-8")
        g_hard_summary.main([str(d / "G_groebner_hard_giac.tsv"), "--out", str(d)])
        self.assertTrue((d / "G_groebner_hard_giac_summary.tsv").exists())
        with self.assertRaises(SystemExit):
            g_hard_summary.summary_name("G_groebner_giac.tsv")


if __name__ == "__main__":
    unittest.main()
