#!/usr/bin/env python3
"""The historical aggregate counts every answer verification level."""
import math
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import history_backfill


class HistoryTests(unittest.TestCase):
    def test_numeric_answers_are_counted_as_verified(self):
        text = ("system\tcase\tstatus\tt_warm_s\n"
                "A\tone\tverified\t1\n"
                "A\ttwo\tverified_numeric\t3\n"
                "A\tthree\tverified_symbolic\t5\n"
                "A\tfour\tverify_timeout\t60\n")
        _, n, counts, total, median = history_backfill.summarize(text)
        self.assertEqual(n, 4)
        self.assertEqual(counts["verified"], 3)
        self.assertTrue(math.isclose(total, 9))
        self.assertTrue(math.isclose(median, 3))

    def test_new_mixed_operations_have_no_aggregate_median(self):
        text = ("system\tcase\top\tstatus\tt_warm_s\tverify_status\n"
                "A\tone\texpand\tverified_numeric\t1\t\n"
                "A\ttwo\tfactor\tverified_numeric\t3\t\n")
        _, _, _, _, median = history_backfill.summarize(text)
        self.assertTrue(math.isnan(median))



if __name__ == "__main__":
    unittest.main()
