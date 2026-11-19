#!/usr/bin/env python3
"""Checks for the LaTeX renderer. Run with python3 -I tools/site/test_latexify.py."""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import latexify  # noqa: E402


class LatexifyTests(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(latexify.latexify("x^2+1"), "x^{2} + 1")
        self.assertEqual(latexify.latexify("(a+b*x)^(3/2)"), "\\left(a + b\\,x\\right)^{3/2}")
        self.assertEqual(latexify.latexify("sqrt(1-x^2)"), "\\sqrt{1 - x^{2}}")
        self.assertEqual(latexify.latexify("1/(x^5-x+1)"), "\\frac{1}{x^{5} - x + 1}")
        self.assertEqual(latexify.latexify("arctan(sqrt(x))"), "\\arctan\\left(\\sqrt{x}\\right)")
        self.assertEqual(latexify.latexify("sin(x)"), "\\sin x")
        self.assertEqual(latexify.latexify("exp(-x)*ln(x)^2"), "\\exp\\left(-x\\right)\\,\\ln x^{2}")
        self.assertEqual(latexify.latexify("-x^2"), "-x^{2}")
        self.assertEqual(latexify.latexify("x - (y - z)"), "x - \\left(y - z\\right)")
        self.assertEqual(latexify.latexify("2*3"), "2\\cdot 3")
        self.assertEqual(latexify.latexify("x1^2 + 2*x1*x2"), "x_{1}^{2} + 2\\,x_{1}\\,x_{2}")

    def test_functions(self):
        self.assertEqual(latexify.latexify("GAMMA(2,a+b*x)"), "\\Gamma\\left(2, a + b\\,x\\right)")
        self.assertEqual(latexify.latexify("integrate(f(x),x,0,1)"), "\\int_{0}^{1} \\operatorname{f}\\left(x\\right)\\,dx")
        self.assertEqual(latexify.latexify("sum(1/n^2,n,1,infinity)"), "\\sum_{n=1}^{\\mathit{infinity}} \\frac{1}{n^{2}}")
        self.assertEqual(latexify.latexify("x**2"), "x^{2}")

    def test_fallback(self):
        self.assertTrue(latexify.latexify("y'' = x y").startswith("\\text{"))
        self.assertIsNone(latexify.integral("y'' = x y"))
        self.assertEqual(latexify.integral("x"), "\\int x\\,dx")


if __name__ == "__main__":
    unittest.main()
