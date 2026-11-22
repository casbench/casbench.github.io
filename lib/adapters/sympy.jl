# SymPy adapter, through SymPyPythonCall.jl (PythonCall, no PyCall).
using SymPyPythonCall
const S = SymPyPythonCall.sympy

const SYSTEM = "SymPy"
@syms x y z u v a b c s t k n
@syms d e f g h m p q r j i A B C D F w   # the parameters of bench F, w for bench I
const VAR = Dict{Symbol,Any}(:x => x, :y => y, :z => z, :u => u, :v => v, :a => a, :b => b, :c => c,
                             :s => s, :t => t, :k => k, :n => n)
VAR[:pi] = SymPyPythonCall.PI
for (vv, obj) in (:d => d, :e => e, :f => f, :g => g, :h => h, :m => m, :p => p, :q => q, :r => r, :j => j, :i => i,
                  :A => A, :B => B, :C => C, :D => D, :F => F, :w => w)
    VAR[vv] = obj
end
isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "mapleish.jl"))
# bench F: sympify the translated text (symbols by name are equal to the @syms ones), then integrate
INTEGRATE_TEXT(integrand::String, var::String, params = nothing) = (t = "integrate(" * Mapleish.translate(integrand, :sympy) * ", " * var * ")"; log_input!(t); S.integrate(S.sympify(Mapleish.translate(integrand, :sympy)), S.Symbol(var)))
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

const PyC = SymPyPythonCall.PythonCall
# reduced Gröbner basis (grevlex) of polynomials given as strings; p == 0 for Q, else GF(p)
isdefined(Main, :Poly) || include(joinpath(@__DIR__, "..", "poly.jl"))
# a polynomial string with its rational coefficients reduced modulo p (SymPy's modulus= wants integers)
function modp_string(s::String, vars::Vector{String}, p::Int)
    f = Poly.parse_poly(s, vars)
    terms = String[]
    for (m, c) in f
        mono = join(("$(vars[i])^$(m[i])" for i in eachindex(m) if m[i] > 0), "*")
        push!(terms, string(Poly.modp(c, p), isempty(mono) ? "" : "*" * mono))
    end
    isempty(terms) ? "0" : join(terms, "+")
end
function GROEBNER(polys::Vector{String}, vars::Vector{String}, p::Int)
    syms = [S.Symbol(v) for v in vars]
    F = [S.sympify(p == 0 ? replace(s, "//" => "/") : modp_string(s, vars, p)) for s in polys]
    G = p == 0 ? S.groebner(F, syms...; order = "grevlex") : S.groebner(F, syms...; order = "grevlex", modulus = p)
    go = getfield(G, :o)
    n = PyC.pyconvert(Int, PyC.pylen(go))
    [PyC.pyconvert(String, PyC.pystr(go.exprs[i])) for i in 0:n-1]
end


struct CodegenAnswer
    values::Vector{Any}
    elapsed::Float64
    text::String
end
Base.string(c::CodegenAnswer) = c.text

stext(s::String) = (t = Mapleish.translate(s, :sympy); log_input!(t); S.sympify(t))
EXPAND_TEXT(s) = S.expand(stext(s))
EXPAND_DIFF_TEXT(s, v) = S.diff(S.expand(stext(s)), S.Symbol(v))
SERIES_TEXT(s, v, x0, nn) = S.series(stext(s), S.Symbol(v), x0, nn + 1).removeO()
SUBS_TEXT(s, rules) = stext(s).subs(Dict(S.Symbol(l) => stext(r) for (l, r) in rules))
EVAL_TEXT(s, pt) = N(stext(s).subs(Dict(S.Symbol(k) => v for (k, v) in pt)))
function CODEGEN_TEXT(s, vars, points)
    fn = S.lambdify([S.Symbol(v) for v in vars], stext(s); modules = "math")
    vals = Any[]; t0 = time_ns()
    for p in points; push!(vals, PyC.pyconvert(Float64, fn(p...))); end
    CodegenAnswer(vals, (time_ns() - t0) / 1e9, "lambdify: $(length(vals)) calls")
end

const OPS = Dict{Symbol,Any}(
    :groebner => GROEBNER,
    :expand_text => EXPAND_TEXT, :expand_diff_text => EXPAND_DIFF_TEXT, :series_text => SERIES_TEXT,
    :subs_text => SUBS_TEXT, :eval_text => EVAL_TEXT, :codegen_text => CODEGEN_TEXT,
    :integrate_text => INTEGRATE_TEXT,
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
# Decimal evaluation is outside the measured call and never passes through
# a binary Float64. Existing inexact answers cannot establish 80 digits.
function EVAL_HIGH_PRECISION(ex, digits::Int, at)
    ex isa AbstractFloat && return nothing
    ex isa Integer && return BigFloat(ex)
    ex isa Sym || return nothing
    try
        Bool(getfield(ex.has(S.Float), :o)) && return nothing
        value = at === nothing ? ex : subs(ex, VAR[:x] => Sym(numerator(at)) / Sym(denominator(at)))
        parse(BigFloat, string(S.N(value, digits)))
    catch
        nothing
    end
end
NTERMS(ex) = ex isa Sym && Bool(ex.is_Add) ? length(ex.args) : 1
NFACTORS(ex) = ex isa Sym && Bool(ex.is_Mul) ? length(ex.args) : 1
IS_EXACT(ex) = occursin("pi", string(ex)) && !occursin(r"\d\.\d", string(ex))
CLEARCACHE() = S.core.cache.clear_cache()
VERSIONS() = ["SymPy" => string(S.__version__), "SymPyPythonCall" => string(pkgversion(SymPyPythonCall))]

function VERIFY_INTEGRAL_COMMAND(answer::String, integrand::String, var::String)
    f = Mapleish.translate(integrand, :sympy)
    a = replace(answer, "^" => "**")
    "simplify(diff(sympify(" * repr(a) * "),Symbol(" * repr(var) * "))-sympify(" * repr(f) * "))"
end
function VERIFY_INTEGRAL(answer::String, integrand::String, var::String)
    f = Mapleish.translate(integrand, :sympy)
    a = replace(answer, "^" => "**")
    string(S.simplify(S.diff(S.sympify(a), S.Symbol(var)) - S.sympify(f)))
end
OPS[:VERIFY_INTEGRAL] = VERIFY_INTEGRAL
