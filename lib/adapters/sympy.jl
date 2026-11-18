# SymPy adapter, through SymPyPythonCall.jl (PythonCall, no PyCall).
using SymPyPythonCall
const S = SymPyPythonCall.sympy

const SYSTEM = "SymPy"
@syms x y z u v a b c s t k n
const VAR = Dict{Symbol,Any}(:x => x, :y => y, :z => z, :u => u, :v => v, :a => a, :b => b, :c => c,
                             :s => s, :t => t, :k => k, :n => n)
VAR[:pi] = SymPyPythonCall.PI
toint(m) = Int(N(m))
# exact rationals must enter SymPy as Sym ratios, not Julia Rationals
sx(e) = e isa Rational ? Sym(numerator(e)) / Sym(denominator(e)) : e

FACTOR(f) = ((uu, fs) = S.factor_list(f); (uu, [(g, toint(m)) for (g, m) in fs]))
SOLVE(l, r, x) = solve(sx(l) - sx(r), x)   # Eq(cos(x), 1/2) overflowed the stack in SymPyPythonCall 0.5
function DIOPHANTINE(lhs, rhs, u, v, k)
    # diophantine returns a set with one tuple (u, v) in a parameter t_0; through
    # SymPyPythonCall, collect flattens that single tuple into its two components
    parts = collect(S.diophantine(lhs - rhs))
    length(parts) == 2 || error("unexpected diophantine result: $parts")
    # the Python set has no order, so the component that belongs to u is the one
    # for which the equation holds identically
    ue, ve = parts[1], parts[2]
    Bool(S.expand(subs(lhs, u => ue, v => ve) - rhs) == 0) || ((ue, ve) = (parts[2], parts[1]))
    fs = free_symbols(ue + ve)
    param = first(filter(q -> !(q in (u, v)), collect(fs)))
    # rename SymPy's parameter t_0 to the problem's k so that the check can substitute it
    (subs(ue, param => k), subs(ve, param => k), k)
end
function DESOLVE_IVP(eq_lhs, eq_rhs, yname, t, y0)
    f = SymFunction(yname)
    sol = S.dsolve(Eq(f(t).diff(t), eq_rhs(f(t))), f(t); ics = Dict(f(0) => y0))
    sol.rhs
end
LAPLACE(f, t, s) = S.laplace_transform(f, t, s; noconds = true)
ILAPLACE(F, s, t) = S.inverse_laplace_transform(F, s, t)
LIMIT(f, x, x0) = limit(f, x => (x0 isa Real && isinf(x0) ? (x0 > 0 ? oo : -oo) : x0))
SERIES(f, x, nn) = S.series(f, x, 0, nn + 1).removeO()
GCD(p, q) = S.gcd(p, q)
RESULTANT(p, q, x) = S.resultant(p, q, x)
DISCRIMINANT(p, x) = S.discriminant(p, x)
GROEBNER(polys, vars) = collect(S.groebner(polys, vars...; order = "lex").exprs)
DET(rows) = S.Matrix([rows[i][j] for i in eachindex(rows), j in eachindex(rows[1])]).det()
EIGENVALS(rows) = collect(keys(S.Matrix([rows[i][j] for i in eachindex(rows), j in eachindex(rows[1])]).eigenvals()))
SUM(f, k, lo, hi) = S.summation(f, (k, lo, hi))
IFACTOR(nn) = S.factorint(Sym(nn))
function ASSUME_SIMPLIFY(expr, x)
    xp = S.symbols("x"; positive = true)
    simplify(subs(expr, x => xp))
end
PARTFRAC(f, x) = apart(f, x)

const OPS = Dict{Symbol,Any}(
    :expand => f -> expand(f),
    :factor => FACTOR,
    :integrate => (f, x) -> integrate(f, x),
    :simplify => f -> simplify(f),
    :solve => SOLVE,
    :diophantine => DIOPHANTINE,
    :desolve_ivp => DESOLVE_IVP,
    :laplace => LAPLACE,
    :ilaplace => ILAPLACE,
    :partfrac => PARTFRAC,
    :limit => LIMIT,
    :series => SERIES,
    :gcd => GCD,
    :resultant => RESULTANT,
    :discriminant => DISCRIMINANT,
    :groebner => GROEBNER,
    :det => DET,
    :eigenvals => EIGENVALS,
    :ztrans => missing,            # SymPy has no Z-transform
    :sum => SUM,
    :ifactor => IFACTOR,
    :assume_simplify => ASSUME_SIMPLIFY,
    :trigsimp => f -> S.trigsimp(f),
    :cfactor => f -> S.factor(f; extension = S.I),
)

function UNSOLVED(op, out)
    str = string(out)
    occursin(r"Integral\(|Limit\(|zoo|AccumBounds|Transform\(|\bSum\(|\bProduct\(|\+ O\(|polylog\(", str) && return true
    out isa AbstractVector && isempty(out) && return true
    false
end

function EVAL(ex, vals)
    ex isa Sym || return ex isa Number ? ex : nothing
    # integer-valued points are substituted as integers (a Piecewise on re(n) needs it)
    pairs = [VAR[vv] => (p isa AbstractFloat && isinteger(p) ? Int(p) : p) for (vv, p) in vals if haskey(VAR, vv)]
    uu = isempty(pairs) ? N(ex) : N(subs(ex, pairs...))   # subs(ex) with no pairs overflows the stack
    uu isa Number && !(uu isa Sym) ? uu : nothing
end
NTERMS(ex) = ex isa Sym && Bool(ex.is_Add) ? length(ex.args) : 1
IS_EXACT(ex) = occursin("pi", string(ex)) && !occursin(r"\d\.\d", string(ex))
CLEARCACHE() = S.core.cache.clear_cache()
VERSIONS() = ["SymPy" => string(S.__version__), "SymPyPythonCall" => string(pkgversion(SymPyPythonCall))]
