# SymJ.jl adapter (pure Julia CAS by J. Verzani, announced October 2026), with
# GruntzLimit.jl for limits and RischIntegrate.jl for integrals, as in SymJ's
# own CAS comparison. Operations whose name is not defined in SymJ are marked
# unavailable at load time, so the coverage table reflects the version pinned
# in the manifest rather than this adapter's guesses.
using SymJ
import GruntzLimit, RischIntegrate, TermInterface
import SpecialFunctions, PolyLog, HypergeometricFunctions

const SYSTEM = "SymJ.jl"
const NAMES = (:x, :y, :z, :u, :v, :a, :b, :c, :s, :t, :k, :n)
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

const OPS = Dict{Symbol,Any}(
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
IS_EXACT(ex) = occursin("π", string(ex)) && !occursin(r"\d\.\d", string(ex))
CLEARCACHE() = nothing
VERSIONS() = ["SymJ" => string(pkgversion(SymJ)), "GruntzLimit" => string(pkgversion(GruntzLimit)),
              "RischIntegrate" => string(pkgversion(RischIntegrate))]
