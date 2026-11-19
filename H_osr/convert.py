#!/usr/bin/env python3
"""Convert the OSR v1 integration rules (osr/Integration/v1/integration.osr.json,
OpenMath 2.0 JSON) into the fixed inputs of bench H, H_osr/rules.tsv:

    python3 -I H_osr/convert.py

Columns: id, legacy_id, real, complex, variables, integrand, result,
conditions, description, where
  integrand   the body of the pattern's lambda, in the Maple-like syntax the
              adapters of bench F translate (lib/mapleish.jl): ^, ln, arctan,
              ... with the rule's variables as symbols (x is the variable);
  result      the certified replacement as a Julia expression over complex
              numbers, with a residual integral int(lambda t. H)(x) written
              osr_int(t -> H, x) (evaluated by numeric quadrature in the check);
  conditions  the rule's conditions as one Julia boolean expression over the
              parameters (isinteger(m) for m in Z), "true" when there are none.
Rules whose variables are not among the parameter symbols the adapters know
are skipped (a few dozen, with names like n2 or a1); the count is printed.
The pinned commit of the submodule is recorded in the header line.
"""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "osr" / "Integration" / "v1" / "integration.osr.json"
OUT = pathlib.Path(__file__).resolve().parent / "rules.tsv"
KNOWN = set("abcdefghmnpqrstijkxABCDF")

MAPLE = {"ln": "ln", "exp": "exp", "sin": "sin", "cos": "cos", "tan": "tan", "sec": "sec", "csc": "csc", "cot": "cot",
         "sinh": "sinh", "cosh": "cosh", "tanh": "tanh", "coth": "coth", "sech": "sech", "csch": "csch",
         "arctan": "arctan", "arcsin": "arcsin", "arccos": "arccos", "arctanh": "arctanh", "arcsinh": "arcsinh",
         "arccosh": "arccosh"}
JULIA = {"ln": "log", "exp": "exp", "sin": "sin", "cos": "cos", "tan": "tan", "sec": "sec", "csc": "csc", "cot": "cot",
         "sinh": "sinh", "cosh": "cosh", "tanh": "tanh", "coth": "coth", "sech": "sech", "csch": "csch",
         "arctan": "atan", "arcsin": "asin", "arccos": "acos", "arctanh": "atanh", "arcsinh": "asinh", "arccosh": "acosh"}


class Unsupported(Exception):
    pass


def head(o):
    if o.get("kind") == "OMA" and o["applicant"].get("kind") == "OMS":
        return o["applicant"]["cd"] + "#" + o["applicant"]["name"]
    return None


def emit(o, julia, bound=()):
    """Print an OpenMath object; julia=True for the Julia text of the result (floats, osr_int)."""
    k = o["kind"]
    if k == "OMI":
        n = o["integer"]
        return f"({n}.0)" if julia else (f"({n})" if n < 0 else str(n))
    if k == "OMF":
        v = o.get("decimal") or o.get("float")
        return f"({v})"
    if k == "OMV":
        return o["name"]
    if k == "OMBIND":
        raise Unsupported("bare lambda")
    if k != "OMA":
        raise Unsupported(f"node {k}")
    h = head(o)
    args = o["arguments"]
    if h is None:
        # application of an object that is itself an application: a residual integral int(lambda t. H) applied to x
        app = o["applicant"]
        if head(app) == "calculus1#int" and app["arguments"][0]["kind"] == "OMBIND":
            if not julia:
                raise Unsupported("residual integral in an integrand")
            lam = app["arguments"][0]
            t = lam["variables"][0]["name"]
            body = emit(lam["object"], julia, bound + (t,))
            return f"osr_int({t} -> ({body}), {emit(args[0], julia)})"
        raise Unsupported("application of a non-symbol")
    if h == "arith1#plus":
        return "(" + "+".join(emit(a, julia) for a in args) + ")"
    if h == "arith1#times":
        return "(" + "*".join(emit(a, julia) for a in args) + ")"
    if h == "arith1#minus":
        return "(" + "-".join(emit(a, julia) for a in args) + ")"
    if h == "arith1#unary_minus":
        return "(-" + emit(args[0], julia) + ")"
    if h == "arith1#divide":
        return "(" + emit(args[0], julia) + "/" + emit(args[1], julia) + ")"
    if h == "arith1#power":
        return "(" + emit(args[0], julia) + ")^(" + emit(args[1], julia) + ")"
    if h == "arith1#root":
        return "(" + emit(args[0], julia) + ")^(1/" + emit(args[1], julia) + ")"
    if h == "arith1#abs":
        return "abs(" + emit(args[0], julia) + ")"
    if h.startswith("transc1#"):
        name = h.split("#")[1]
        table = JULIA if julia else MAPLE
        if name not in table:
            raise Unsupported(name)
        return table[name] + "(" + ", ".join(emit(a, julia) for a in args) + ")"
    if h == "nums1#pi":
        return "pi" if julia else "Pi"
    if h == "nums1#e":
        return "exp(1.0)" if julia else "exp(1)"
    if h == "calculus1#int":
        raise Unsupported("unapplied residual integral")
    raise Unsupported(h)


def condition(o):
    h = head(o)
    args = o["arguments"]
    if h == "relation1#neq":
        return "(" + emit(args[0], True) + " != " + emit(args[1], True) + ")"
    if h == "relation1#eq":
        return "(" + emit(args[0], True) + " == " + emit(args[1], True) + ")"
    if h == "relation1#gt":
        return "(" + emit(args[0], True) + " > " + emit(args[1], True) + ")"
    if h == "relation1#lt":
        return "(" + emit(args[0], True) + " < " + emit(args[1], True) + ")"
    if h == "relation1#geq":
        return "(" + emit(args[0], True) + " >= " + emit(args[1], True) + ")"
    if h == "relation1#leq":
        return "(" + emit(args[0], True) + " <= " + emit(args[1], True) + ")"
    if h == "set1#in":
        return "isinteger(" + emit(args[0], True) + ")"
    if h == "logic1#and":
        return "(" + " && ".join(condition(a) for a in args) + ")"
    if h == "logic1#or":
        return "(" + " || ".join(condition(a) for a in args) + ")"
    if h == "logic1#not":
        return "(!" + condition(args[0]) + ")"
    raise Unsupported(f"condition {h}")


def status(rule, domain):
    for v in rule["verification"]:
        if v["domain"] == domain:
            return v["status"]
    return "none"


def main():
    d = json.load(open(SRC, encoding="utf-8"))
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=SRC.parents[1], capture_output=True, text=True).stdout.strip()
    rows, skipped = [], {}
    for r in d["rules"]:
        names = [v["name"] for v in r["variables"]]
        pat = r["pattern"]
        try:
            if head(pat) != "calculus1#int" or pat["arguments"][0]["kind"] != "OMBIND":
                raise Unsupported("pattern is not int(lambda)")
            lam = pat["arguments"][0]
            var = lam["variables"][0]["name"]
            if var != "x" or any(n not in KNOWN for n in names):
                raise Unsupported("variable names")
            integrand = emit(lam["object"], False)
            rep = r["replacement"]
            if rep["kind"] != "OMBIND":
                raise Unsupported("replacement is not a lambda")
            result = emit(rep["object"], True)
            conds = " && ".join(condition(c) for c in r["conditions"]) or "true"
        except Unsupported as ex:
            skipped[str(ex)] = skipped.get(str(ex), 0) + 1
            continue
        rows.append([r["id"], r["legacy_id"], status(r, "real"), status(r, "complex"), " ".join(names),
                     integrand, result, conds, r.get("description", "").replace("\t", " ").replace("\n", " ")])
    with open(OUT, "w", encoding="utf-8") as f:
        digest = next((v.get("source_digest", "") for r in d["rules"] for v in r["verification"] if v.get("source_digest")), "")
        f.write(f"# OSR v1 integration rules, osr/Integration at {commit} (Verification report {digest}), converted by H_osr/convert.py\n")
        f.write("id\tlegacy_id\treal\tcomplex\tvariables\tintegrand\tresult\tconditions\tdescription\n")
        for row in rows:
            f.write("\t".join(str(c) for c in row) + "\n")
    print(f"{len(rows)} rules written to {OUT}; skipped: {skipped}")


if __name__ == "__main__":
    main()
