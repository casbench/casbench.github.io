#!/usr/bin/env python3
"""Render the Maple-like expression text of the benches as LaTeX, for the site.

    latexify("(a+b*x)^(3/2)/sqrt(1-x^2)")  ->  \\frac{(a+b x)^{3/2}}{\\sqrt{1-x^{2}}}

A small recursive-descent parser (numbers, symbols, function calls, + - * / ^,
unary minus, parentheses) and a printer that writes fractions, roots, powers
in braces, known function names with a backslash, Greek letters and a thin
space for products. Anything the parser does not accept is returned verbatim
inside \\text{} so that a page never breaks.
"""
import re

FUNCS = {"sin", "cos", "tan", "cot", "sec", "csc", "sinh", "cosh", "tanh", "coth", "exp", "ln", "log",
         "arcsin", "arccos", "arctan", "arcsinh", "arccosh", "arctanh", "arccot", "arcsec", "arccsc",
         "arccoth", "arcsech", "arccsch", "sech", "csch", "min", "max", "gcd", "det"}
OPNAMES = {"arcsin": "\\arcsin", "arccos": "\\arccos", "arctan": "\\arctan", "arcsinh": "\\operatorname{arcsinh}",
           "arccosh": "\\operatorname{arccosh}", "arctanh": "\\operatorname{arctanh}", "arccot": "\\operatorname{arccot}",
           "arcsec": "\\operatorname{arcsec}", "arccsc": "\\operatorname{arccsc}", "arccoth": "\\operatorname{arccoth}",
           "arcsech": "\\operatorname{arcsech}", "arccsch": "\\operatorname{arccsch}", "sech": "\\operatorname{sech}",
           "csch": "\\operatorname{csch}", "ln": "\\ln", "log": "\\log", "exp": "\\exp"}
GREEK = {"alpha", "beta", "gamma", "delta", "epsilon", "theta", "lambda", "mu", "nu", "pi", "rho", "sigma", "tau", "phi", "omega", "Pi"}
SPECIAL = {"GAMMA": "\\Gamma", "Zeta": "\\zeta", "Ei": "\\operatorname{Ei}", "Si": "\\operatorname{Si}", "Ci": "\\operatorname{Ci}",
           "erf": "\\operatorname{erf}", "erfc": "\\operatorname{erfc}", "erfi": "\\operatorname{erfi}", "polylog": "\\operatorname{Li}",
           "LambertW": "W", "EllipticF": "F", "EllipticE": "E", "EllipticPi": "\\Pi", "hypergeom": "{}_pF_q", "FresnelC": "C",
           "FresnelS": "S", "Shi": "\\operatorname{Shi}", "Chi": "\\operatorname{Chi}", "BesselJ": "J", "besselJ": "J", "Dirac": "\\delta",
           "Heaviside": "H", "abs": "abs", "sqrt": "sqrt", "root": "root", "floor": "floor", "ceil": "ceil", "sign": "\\operatorname{sign}",
           "sgn": "\\operatorname{sgn}", "diff": "diff", "integrate": "int", "int": "int", "sum": "sum", "product": "prod", "limit": "lim"}

TOKEN = re.compile(r"\s*(?:(\d+\.\d+|\d+)|([A-Za-z_][A-Za-z_0-9]*)|(\*\*|[-+*/^(),=\[\]]))")


class Unsupported(Exception):
    pass


def tokenize(s):
    toks, pos = [], 0
    while pos < len(s):
        m = TOKEN.match(s, pos)
        if not m or m.end() == pos:
            raise Unsupported(s[pos:pos + 10])
        pos = m.end()
        if m.group(1):
            toks.append(("num", m.group(1)))
        elif m.group(2):
            toks.append(("id", m.group(2)))
        else:
            toks.append(("op", "^" if m.group(3) == "**" else m.group(3)))
    toks.append(("eof", ""))
    return toks


class Parser:
    def __init__(self, s):
        self.t = tokenize(s)
        self.i = 0

    def peek(self):
        return self.t[self.i]

    def take(self, kind=None, text=None):
        k, v = self.t[self.i]
        if (kind and k != kind) or (text and v != text):
            raise Unsupported(f"expected {text or kind}, got {v!r}")
        self.i += 1
        return v

    # precedence: sum < product < unary < power < atom
    def expr(self):
        node = self.term()
        while self.peek() == ("op", "+") or self.peek() == ("op", "-"):
            op = self.take()
            node = ("bin", op, node, self.term())
        return node

    def term(self):
        node = self.unary()
        while self.peek() == ("op", "*") or self.peek() == ("op", "/"):
            op = self.take()
            node = ("bin", op, node, self.unary())
        return node

    def unary(self):
        if self.peek() == ("op", "-"):
            self.take()
            return ("neg", self.unary())
        if self.peek() == ("op", "+"):
            self.take()
            return self.unary()
        return self.power()

    def power(self):
        base = self.atom()
        if self.peek() == ("op", "^"):
            self.take()
            return ("pow", base, self.unary())
        return base

    def atom(self):
        k, v = self.peek()
        if k == "num":
            self.take()
            return ("num", v)
        if k == "id":
            self.take()
            if self.peek() == ("op", "("):
                self.take()
                args = []
                if self.peek() != ("op", ")"):
                    args.append(self.expr())
                    while self.peek() == ("op", ","):
                        self.take()
                        args.append(self.expr())
                self.take("op", ")")
                return ("call", v, args)
            return ("sym", v)
        if k == "op" and v == "(":
            self.take()
            node = self.expr()
            self.take("op", ")")
            return ("paren", node)
        if k == "op" and v == "[":
            self.take()
            items = []
            if self.peek() != ("op", "]"):
                items.append(self.expr())
                while self.peek() == ("op", ","):
                    self.take()
                    items.append(self.expr())
            self.take("op", "]")
            return ("list", items)
        raise Unsupported(f"unexpected {v!r}")


def sym_tex(name):
    if name in GREEK:
        return "\\" + name if name != "Pi" else "\\pi"
    m = re.match(r"^([A-Za-z]+)(\d+)$", name)
    if m:
        return f"{m.group(1)}_{{{m.group(2)}}}"
    return name if len(name) == 1 else "\\mathit{" + name + "}"


def is_simple(node):
    return node[0] in ("num", "sym") or (node[0] == "call" and node[1] not in ("sqrt", "root"))


def tex(node, in_frac=False):
    k = node[0]
    if k == "num":
        return node[1]
    if k == "sym":
        return sym_tex(node[1])
    if k == "paren":
        return "\\left(" + tex(node[1]) + "\\right)"
    if k == "list":
        return "\\left[" + ", ".join(tex(n) for n in node[1]) + "\\right]"
    if k == "neg":
        inner = node[1]
        t = tex(inner)
        return "-" + (t if inner[0] != "bin" else "\\left(" + t + "\\right)")
    if k == "pow":
        base, exp = node[1], node[2]
        b = tex(base)
        if base[0] in ("bin", "neg", "pow"):
            b = "\\left(" + b + "\\right)"
        inner = exp[1] if exp[0] == "paren" else exp          # the braces of the exponent replace its parentheses
        if inner[0] == "bin" and inner[1] == "/" and inner[2][0] == "num" and inner[3][0] == "num":
            e = inner[2][1] + "/" + inner[3][1]
        elif inner[0] == "neg" and inner[1][0] == "num":
            e = "-" + inner[1][1]
        else:
            e = tex(inner)
        return b + "^{" + e + "}"
    if k == "call":
        name, args = node[1], node[2]
        if name == "sqrt" and len(args) == 1:
            return "\\sqrt{" + tex(args[0]) + "}"
        if name == "root" and len(args) == 2:
            return "\\sqrt[" + tex(args[1]) + "]{" + tex(args[0]) + "}"
        if name == "abs" and len(args) == 1:
            return "\\left|" + tex(args[0]) + "\\right|"
        if name in ("integrate", "int") and len(args) >= 2:
            body = tex(args[0])
            var = tex(args[1])
            if len(args) == 4:
                return "\\int_{" + tex(args[2]) + "}^{" + tex(args[3]) + "} " + body + "\\,d" + var
            return "\\int " + body + "\\,d" + var
        if name == "diff" and len(args) == 2:
            return "\\frac{d}{d" + tex(args[1]) + "}\\left(" + tex(args[0]) + "\\right)"
        if name in ("sum", "product") and len(args) == 4:
            big = "\\sum" if name == "sum" else "\\prod"
            return big + "_{" + tex(args[1]) + "=" + tex(args[2]) + "}^{" + tex(args[3]) + "} " + tex(args[0])
        if name == "limit" and len(args) == 3:
            return "\\lim_{" + tex(args[1]) + "\\to " + tex(args[2]) + "} " + tex(args[0])
        if name in FUNCS:
            head = OPNAMES.get(name, "\\" + name)
            a = args[0] if len(args) == 1 else None
            if a is not None and a[0] in ("sym", "num"):
                return head + " " + tex(a)
            return head + "\\left(" + ", ".join(tex(x) for x in args) + "\\right)"
        head = SPECIAL.get(name)
        if head is None:
            head = "\\operatorname{" + name.replace("_", "\\_") + "}"
        return head + "\\left(" + ", ".join(tex(x) for x in args) + "\\right)"
    if k == "bin":
        op, l, r = node[1], node[2], node[3]
        if op == "+":
            return tex(l) + " + " + tex(r)
        if op == "-":
            rt = tex(r)
            if r[0] == "bin" and r[1] in ("+", "-"):
                rt = "\\left(" + rt + "\\right)"
            return tex(l) + " - " + rt
        if op == "*":
            lt, rt = tex(l), tex(r)
            if l[0] == "bin" and l[1] in ("+", "-"):
                lt = "\\left(" + lt + "\\right)"
            if r[0] == "bin" and r[1] in ("+", "-"):
                rt = "\\left(" + rt + "\\right)"
            sep = "\\cdot " if (l[0] == "num" and r[0] == "num") else "\\,"
            return lt + sep + rt
        if op == "/":
            unwrap = lambda n: n[1] if n[0] == "paren" else n       # the fraction bar replaces the parentheses
            return "\\frac{" + tex(unwrap(l)) + "}{" + tex(unwrap(r)) + "}"
    raise Unsupported(k)


def latexify(s):
    """LaTeX for the expression text `s`; the text inside \\text{} when it cannot be parsed."""
    try:
        p = Parser(s)
        node = p.expr()
        if p.peek()[0] != "eof":
            raise Unsupported("trailing")
        return tex(node)
    except Unsupported:
        return "\\text{" + s.replace("\\", "\\textbackslash ").replace("{", "\\{").replace("}", "\\}") + "}"


def integral(s, var="x"):
    """The integral of the expression text as display LaTeX, or None when the text does not parse."""
    try:
        p = Parser(s)
        node = p.expr()
        if p.peek()[0] != "eof":
            return None
        return "\\int " + tex(node) + "\\,d" + var
    except Unsupported:
        return None


if __name__ == "__main__":
    import sys
    for arg in sys.argv[1:]:
        print(latexify(arg))
