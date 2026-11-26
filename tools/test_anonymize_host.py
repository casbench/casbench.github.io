#!/usr/bin/env python3
"""Publishing a host under a neutral name leaves no trace of the machine's own name or of its user."""
import hashlib
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import anonymize_host

ENV = """# environment capture 2026-11-23T16:39:50Z
Julia Version 1.13.3
Platform Info:
  OS: Linux (x86_64-linux-gnu)
  CPU: Example CPU:
                 speed         user         nice          sys         idle          irq
       #1-16  2005 MHz    1909187 s      88667 s     428039 s   13082549 s      59339 s
  Memory: 30.6 GB (16653.875 MB free)
  Uptime: 983244.93 sec
  Load Avg:  6.07  2.48  1.09
  WORD_SIZE: 64
Threads: 1 default, 0 interactive, 1 GC (on 16 virtual cores)
Environment:
  JULIA_NUM_THREADS = 1
  HOME = /home/someone
  PATH = /home/someone/.nix-profile/bin:/usr/bin
  TERM = dumb
Architecture:                            x86_64
"""


class AnonymizeTests(unittest.TestCase):
    def make_tree(self, root):
        res = root / "results"
        old = res / "box7"
        old.mkdir(parents=True)
        (old / "F_x_giac.tsv").write_text("bench\trun\nF\t20261123_box7_main\n", encoding="utf-8")
        (old / "machine.txt").write_text("run_id\t20261123_box7_main\nhost\tBOX7\nhost_slug\tbox7\n", encoding="utf-8")
        (old / "environment.txt").write_text(ENV, encoding="utf-8")
        written = hashlib.sha256((old / "F_x_giac.tsv").read_bytes()).hexdigest()
        (old / "SOURCES.tsv").write_text(
            "# The BOX7 campaign\nfile\trun_directory\tcommit\trun_id\tsha256\n"
            "F_x_giac.tsv\tbox7-main\tabc\t20261123_box7_main\t" + written + "\n", encoding="utf-8")
        (res / "history.tsv").write_text("date\thost\tbench\n2026-11-23\tbox7\tF\n2026-11-20\tref\tF\n", encoding="utf-8")
        ref = res / "ref"
        ref.mkdir()
        (ref / "environment.txt").write_text(ENV, encoding="utf-8")
        return res

    def test_rename_leaves_no_old_name(self):
        with tempfile.TemporaryDirectory() as d:
            res = self.make_tree(pathlib.Path(d))
            anonymize_host.rename_host(res, "box7", "host-2")
            self.assertFalse((res / "box7").exists())
            for p in [*(res / "host-2").iterdir(), res / "history.tsv"]:
                self.assertNotIn("box7", p.read_text(encoding="utf-8").lower(), p.name)
            machine = (res / "host-2" / "machine.txt").read_text(encoding="utf-8")
            self.assertIn("host\thost-2\n", machine)
            self.assertIn("2026-11-20\tref\tF", (res / "history.tsv").read_text(encoding="utf-8"))

    def test_sources_checksums_follow_the_published_files(self):
        with tempfile.TemporaryDirectory() as d:
            res = self.make_tree(pathlib.Path(d))
            original = hashlib.sha256((res / "box7" / "F_x_giac.tsv").read_bytes()).hexdigest()
            anonymize_host.rename_host(res, "box7", "host-2")
            rows = [l.split("\t") for l in (res / "host-2" / "SOURCES.tsv").read_text(encoding="utf-8").splitlines()
                    if not l.startswith("#")]
            header, row = rows[0], dict(zip(rows[0], rows[1]))
            self.assertEqual(header[-1], "sha256_as_written")
            self.assertEqual(row["sha256"], hashlib.sha256((res / "host-2" / "F_x_giac.tsv").read_bytes()).hexdigest())
            self.assertEqual(row["sha256_as_written"], original)

    def test_rename_refuses_an_existing_target(self):
        with tempfile.TemporaryDirectory() as d:
            res = self.make_tree(pathlib.Path(d))
            (res / "host-2").mkdir()
            with self.assertRaises(SystemExit):
                anonymize_host.rename_host(res, "box7", "host-2")

    def test_environment_keeps_versions_and_drops_the_user(self):
        out = anonymize_host.scrub_environment(ENV)
        for kept in ("Julia Version 1.13.3", "CPU: Example CPU", "Memory: 30.6 GB", "WORD_SIZE: 64",
                     "JULIA_NUM_THREADS = 1", "TERM = dumb", "Architecture:"):
            self.assertIn(kept, out)
        for dropped in ("/home/someone", "Uptime", "Load Avg", "1909187", "HOME ="):
            self.assertNotIn(dropped, out)
        self.assertEqual(anonymize_host.scrub_environment(out), out)


if __name__ == "__main__":
    unittest.main()
