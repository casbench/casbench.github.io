# SymJ.jl adapter (pure Julia CAS by J. Verzani, announced October 2026), with
# GruntzLimit.jl for limits and RischIntegrate.jl for integrals, as in SymJ's
# own CAS comparison. Operations whose name is not defined in SymJ are marked
# unavailable at load time, so the coverage table reflects the version pinned
# in the manifest rather than this adapter's guesses.
using SymJ
import GruntzLimit, RischIntegrate, TermInterface
import SpecialFunctions, PolyLog, HypergeometricFunctions

const SYSTEM = "SymJ.jl"
const NAMES = (:x, :y, :z, :u, :v, :a, :b, :c, :s, :t, :k, :n, :d, :e, :f, :g, :h, :m, :p, :q, :r, :j, :i, :A, :B, :C, :D, :F, :w)   # the last ones: parameters of bench F
const VAR = Dict{Symbol,Any}(vv => Sym(vv) for vv in NAMES)
VAR[:pi] = Sym(π)
sym(e) = e isa Sym ? e : Sym(e)
gens(f...) = sort!(collect(union(free_symbols.(sym.(f))...)); by = string)
getop(name::Symbol) = isdefined(SymJ, name) ? getfield(SymJ, name) : missing
opt(name::Symbol, f) = getop(name) === missing ? missing : f

function FACTOR(f)
    unit, fs = factor(Poly(f, gens(f)...))
    (Sym(unit), [(Sym(p), m) for (p, m) in fs])
end
_isequation(cc) = cc isa SymJ.Relation && cc.op === :eq
generic(r) = r isa SymJ.Cases ? last(r[findlast(p -> !any(_isequation, p.first), collect(r))]) : r
SOLVE(l, r, x) = generic(solve(sym(l) ~ sym(r), x))
LIMIT(f, x, x0) = GruntzLimit.gruntz_limit(f, x, x0)
SERIES(f, x, nn) = getop(:series)(f, x, 0, nn + 1)   # SymJ's last argument is the order of the O() term
GCD(p, q) = gcd(p, q)
DET(rows) = getop(:det)(Sym[rows[i][j] for i in eachindex(rows), j in eachindex(rows[1])])
function DESOLVE_IVP(eq_lhs, eq_rhs, yname, t, y0)
    # SymJ.dsolve(eq, y(x), ics...) with initial conditions as pairs; returns y(t) ~ solution
    f = getop(:dsolve)
    @syms yy()
    r = f(diff(yy(t), t) ~ eq_rhs(yy(t)), yy(t), yy(0) => y0)
    r isa SymJ.Relation ? r.rhs : r
end

isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "mapleish.jl"))
# bench F: the translated text evaluated as Julia with the symbols bound to the Sym variables, then RischIntegrate
function INTEGRATE_TEXT(integrand::String, var::String, params = nothing)
    ex = Mapleish.julia_expr(integrand)
    log_input!("integrate(" * string(ex) * ", " * var * ")   # RischIntegrate")
    bindings = Expr(:block, (Expr(:(=), vv, obj) for (vv, obj) in VAR if vv != :pi)...)
    f = Core.eval(Main, Expr(:let, bindings, ex))
    RischIntegrate.integrate(sym(f), VAR[Symbol(var)])
end


struct CodegenAnswer
    values::Vector{Any}
    elapsed::Float64
    text::String
end
Base.string(c::CodegenAnswer) = c.text

function sym_from_text(s::String)
    ex = Mapleish.julia_expr(s)
    bindings = Expr(:block, (Expr(:(=), vv, obj) for (vv, obj) in VAR if vv != :pi)...)
    sym(Core.eval(Main, Expr(:let, bindings, ex)))
end
EXPAND_TEXT(s) = expand(sym_from_text(s))
EXPAND_DIFF_TEXT(s, v) = diff(expand(sym_from_text(s)), VAR[Symbol(v)])
SERIES_TEXT(s, v, x0, nn) = isdefined(SymJ, :series) ? SymJ.series(sym_from_text(s), VAR[Symbol(v)], x0, nn) : error("no series in SymJ")
SUBS_TEXT(s, rules) = subs(sym_from_text(s), (VAR[Symbol(l)] => sym_from_text(r) for (l, r) in rules)...)
EVAL_TEXT(s, pt) = N(subs(sym_from_text(s), (VAR[Symbol(k)] => v for (k, v) in pt)...))
function CODEGEN_TEXT(s, vars, points)
    isdefined(SymJ, :lambdify) || error("no lambdify in SymJ")
    f = SymJ.lambdify(sym_from_text(s), [VAR[Symbol(v)] for v in vars])
    vals = Any[]; t0 = time_ns()
    for p in points; push!(vals, Base.invokelatest(f, p...)); end
    CodegenAnswer(vals, (time_ns() - t0) / 1e9, "lambdify: $(length(vals)) calls")
end

const OPS = Dict{Symbol,Any}(
    :integrate_text => INTEGRATE_TEXT,
    :expand_text => EXPAND_TEXT, :expand_diff_text => EXPAND_DIFF_TEXT, :series_text => SERIES_TEXT,
    :subs_text => SUBS_TEXT, :eval_text => EVAL_TEXT, :codegen_text => CODEGEN_TEXT,
    :expand => f -> expand(f),
    :factor => FACTOR,
    :integrate => (f, x) -> RischIntegrate.integrate(f, x),
    :simplify => f -> simplify(f),
    :solve => SOLVE,
    :diophantine => missing,
    :desolve_ivp => opt(:dsolve, DESOLVE_IVP),
    :laplace => opt(:laplace, (f, t, s) -> getop(:laplace)(f, t, s)),
    :ilaplace => opt(:ilaplace, (F, s, t) -> getop(:ilaplace)(F, s, t)),
    :partfrac => (f, x) -> apart(f, x),
    :limit => LIMIT,
    :series => opt(:series, SERIES),
    :gcd => GCD,
    :resultant => opt(:resultant, (p, q, x) -> getop(:resultant)(p, q, x)),
    :discriminant => opt(:discriminant, (p, x) -> getop(:discriminant)(p, x)),
    :groebner => opt(:groebner, (polys, vars) -> getop(:groebner)(polys, vars...)),   # groebner(F, vars...; order = :lex)
    :det => opt(:det, DET),
    :eigenvals => opt(:eigenvals, rows -> getop(:eigenvals)(Sym[rows[i][j] for i in eachindex(rows), j in eachindex(rows[1])])),
    :ztrans => missing,
    :sum => opt(:summation, (f, k, lo, hi) -> getop(:summation)(f, (k, lo, hi))),
    :ifactor => missing,
    :assume_simplify => missing,
    :trigsimp => f -> simplify(f),
    :cfactor => missing,
)

UNSOLVED(op, out) = out === nothing || (out isa AbstractVector && isempty(out)) || occursin(r"\bSum\(|\bProduct\(|\bIntegral\(", string(out))

function EVAL(ex, vals)
    ex isa Number && !(ex isa Sym) && return ex
    ex isa RischIntegrate.IntegralWithRootSums && return ex(vals[Symbol(string(ex.var))])
    uu = N(subs(sym(ex), (VAR[vv] => p for (vv, p) in vals if haskey(VAR, vv))...))
    uu isa Number ? uu : nothing
end
NTERMS(ex) = ex isa Sym && TermInterface.iscall(ex) && TermInterface.operation(ex) === (+) ?
    length(TermInterface.arguments(ex)) : 1
NFACTORS(ex) = ex isa Sym && TermInterface.iscall(ex) && TermInterface.operation(ex) === (*) ?
    length(TermInterface.arguments(ex)) : 1
IS_EXACT(ex) = occursin("π", string(ex)) && !occursin(r"\d\.\d", string(ex))
CLEARCACHE() = nothing
# warm-up (see symbolics.jl): the compilation of the integration path is paid here, not by the first case
try
    RischIntegrate.integrate(sym(VAR[:x]^2 + 1), VAR[:x]); expand((VAR[:x] + VAR[:y])^3)
catch
end
VERSIONS() = ["SymJ" => string(pkgversion(SymJ)), "GruntzLimit" => string(pkgversion(GruntzLimit)),
              "RischIntegrate" => string(pkgversion(RischIntegrate))]
