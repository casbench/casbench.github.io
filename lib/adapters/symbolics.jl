# Symbolics.jl adapter. Symbolics has no symbolic integration of its own in
# the version used here, so integrals go through RischIntegrate.jl and limits
# through GruntzLimit.jl, both of which operate on SymbolicUtils terms (this
# is the pairing used in SymJ.jl's own CAS comparison). Polynomial
# factorisation uses Symbolics.factor_use_nemo (Nemo.jl extension). Integer
# factorisation is delegated to Primes.jl, the package Symbolics.factor
# forwards to.
using Symbolics, Nemo, Groebner, Primes
import GruntzLimit, RischIntegrate, TermInterface, SymbolicUtils
using Symbolics: unwrap
using LinearAlgebra: det
using TermInterface: iscall, operation, arguments

const SYSTEM = "Symbolics.jl"
@variables x y z u v a b c s t k n
const VAR = Dict{Symbol,Any}(:x => x, :y => y, :z => z, :u => u, :v => v, :a => a, :b => b, :c => c,
                             :s => s, :t => t, :k => k, :n => n)
VAR[:pi] = Num(SymbolicUtils.maketerm(typeof(unwrap(x)), identity, Any[π], nothing))
num(e) = e isa Num ? e : Num(e)

function FACTOR(f)
    unit, fs = Symbolics.factor_use_nemo(f)
    out = map(fs) do g
        e = unwrap(g)
        kk = iscall(e) && operation(e) === (^) ? SymbolicUtils.unwrap_const(arguments(e)[2]) : nothing
        kk isa Integer ? (Num(arguments(e)[1]), Int(kk)) : (g, 1)
    end
    (unit, out)
end
SOLVE(l, r, x) = symbolic_solve(num(l) ~ num(r), x)
# Symbolics 7.49 ships `limit` (through SymbolicLimits.jl, on unwrapped terms); bench D
# uses it as shipped. GruntzLimit.jl, used by SymJ's own comparison for Symbolics, is
# a separate package and is not wired here.
LIMIT(f, x, x0) = Symbolics.limit(unwrap(f), unwrap(x), x0)
# Laplace transforms were added to Symbolics during 2026: laplace(expr, f, t, F, s)
# with f and F symbolic function symbols
SymbolicUtils.@syms 𝑓(t) 𝐹(s)
LAPLACE(f, t, s) = Symbolics.laplace(f, 𝑓, t, 𝐹, s)
ILAPLACE(F, s, t) = Symbolics.inverse_laplace(F, 𝐹, s, 𝑓, t)
SERIES(f, x, nn) = taylor(f, x, 0:nn)
GCD(p, q) = nothing   # no polynomial gcd on Num
GROEBNER(polys, vars) = groebner_basis(polys)
DET(rows) = det(Num[rows[i][j] for i in eachindex(rows), j in eachindex(rows[1])])
IFACTOR(nn) = Primes.factor(nn)
PARTFRAC(f, x) = partial_frac_decomposition(f, x)
SymbolicUtils.@syms 𝑦(t)::Real
function DESOLVE_IVP(eq_lhs, eq_rhs, yname, t, y0)
    # y' = eq_rhs(y) with y(0) = y0, solved by the Laplace transform method
    # (laplace_solve_ode(eq, f, t, [f(0)]), as in its docstring)
    D = Differential(t)
    Symbolics.laplace_solve_ode(D(𝑦(t)) ~ eq_rhs(𝑦(t)), 𝑦, t, [y0])
end

const OPS = Dict{Symbol,Any}(
    :expand => f -> Symbolics.expand(f),
    :factor => FACTOR,
    :integrate => (f, x) -> RischIntegrate.integrate(unwrap(f), unwrap(x)),
    :simplify => f -> Symbolics.simplify(f),
    :solve => SOLVE,
    :diophantine => missing,
    :desolve_ivp => DESOLVE_IVP,
    :laplace => LAPLACE,
    :ilaplace => ILAPLACE,
    :partfrac => PARTFRAC,
    :limit => LIMIT,
    :series => SERIES,
    :gcd => missing,
    :resultant => missing,
    :discriminant => missing,
    :groebner => GROEBNER,
    :det => DET,
    :eigenvals => missing,
    :ztrans => missing,
    :sum => missing,
    :ifactor => IFACTOR,
    :assume_simplify => missing,
    :trigsimp => f -> Symbolics.simplify(f),
    :cfactor => missing,
)

UNSOLVED(op, out) = out === nothing || occursin("roots_of", string(out)) ||
    (op === :solve && out isa AbstractVector && isempty(out))

function EVAL(ex, vals)
    ex isa RischIntegrate.IntegralWithRootSums && return ex(vals[Symbol(string(ex.var))])
    isplain(z) = (z isa Real || z isa Complex) && !(z isa Num) && !(z isa SymbolicUtils.BasicSymbolic)
    isplain(ex) && return ex
    ex isa Num || ex isa SymbolicUtils.BasicSymbolic || return nothing
    # real values first; if that fails (log of a negative, say), complex ones
    for cplx in (false, true)
        uu = try
            # SymbolicUtils.substitute with fold folds atan(0.31) to a Float64;
            # Symbolics.substitute on a Num does not
            d = Dict{Any,Any}(unwrap(VAR[vv]) => (cplx ? complex(p) : p) for (vv, p) in vals if haskey(VAR, vv))
            r = SymbolicUtils.substitute(unwrap(ex), d; fold = Val(true))
            r isa SymbolicUtils.BasicSymbolic ? SymbolicUtils.unwrap_const(r) : r
        catch
            nothing
        end
        isplain(uu) && return uu
    end
    nothing
end
function NTERMS(ex)
    e = unwrap(ex)
    iscall(e) && operation(e) === (+) ? length(arguments(e)) : 1
end
IS_EXACT(ex) = occursin("π", string(ex)) && !occursin(r"\d\.\d", string(ex))
CLEARCACHE() = nothing
VERSIONS() = ["Symbolics" => string(pkgversion(Symbolics)), "SymbolicUtils" => string(pkgversion(SymbolicUtils)),
              "Nemo" => string(pkgversion(Nemo)), "Groebner" => string(pkgversion(Groebner)),
              "GruntzLimit" => string(pkgversion(GruntzLimit)), "RischIntegrate" => string(pkgversion(RischIntegrate)),
              "Primes" => string(pkgversion(Primes))]
