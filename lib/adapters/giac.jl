# Giac.jl adapter. Every operation goes through `invoke_cmd`, the universal
# command gateway, with GiacExpr arguments (the direct-Gen fast path).
using Giac
using LinearAlgebra: det

const SYSTEM = "Giac.jl"
@giac_var x y z u v a b c s t k n
# the parameters of bench F; `e` and `i` are constants in Giac, so those two symbols are ee and ii
@giac_var d f g h m p q r j A B C D F ee ii
const VAR = Dict{Symbol,Any}(:x => x, :y => y, :z => z, :u => u, :v => v, :a => a, :b => b, :c => c,
                             :s => s, :t => t, :k => k, :n => n)
VAR[:pi] = giac_eval("pi")
for (vv, obj) in (:d => d, :f => f, :g => g, :h => h, :m => m, :p => p, :q => q, :r => r, :j => j,
                  :A => A, :B => B, :C => C, :D => D, :F => F, :e => ee, :i => ii)
    VAR[vv] = obj
end
isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "mapleish.jl"))
# bench F: an integrand in the Maple-like text of the 12000.org files
function INTEGRATE_TEXT(integrand::String, var::String, params = nothing)
    s = Mapleish.translate(integrand, :giac)
    s = replace(s, r"\be\b" => "ee", r"\bi\b" => "ii")
    giac_eval("integrate(" * s * "," * var * ")")
end

gx(e) = e isa GiacExpr ? e :
    e isa Rational ? giac_eval("($(numerator(e)))/($(denominator(e)))") :
    e isa Real && isinf(e) ? giac_eval(e > 0 ? "+infinity" : "-infinity") : giac_eval(string(e))
# vector-valued results as a Julia vector of GiacExpr / numbers
elements(r) = (v = to_julia(r); v isa AbstractVector ? v : [v])
cmd(c, args...) = invoke_cmd(c, args...)
toint(m) = Int(to_julia(gx(m)))
r12(p::Real) = round(p; sigdigits = 12)
r12(p::Complex) = complex(r12(real(p)), r12(imag(p)))

# polynomial factors as (unit, [(factor, multiplicity), ...]); numeric constants
# in Giac's `factors` list are folded into the unit
function FACTOR(f)
    L = to_julia(cmd(:factors, f))
    unit = 1
    out = Any[]
    for i in 1:2:length(L)
        g, m = L[i], toint(L[i + 1])
        gn = g isa GiacExpr ? to_julia(g) : g
        if gn isa Number
            unit *= gn^m
        else
            push!(out, (g, m))
        end
    end
    (unit, out)
end
SOLVE(l, r, x) = elements(cmd(:solve, cmd(:equal, gx(l), gx(r)), x))
# isolve(a*u + b*v = c, k): returns [u = ..., v = ...] parametrised by k
function DIOPHANTINE(lhs, rhs, u, v, k)
    r = elements(cmd(:isolve, cmd(:equal, gx(lhs), gx(rhs)), k))
    (cmd(:rhs, r[1]), cmd(:rhs, r[2]), k)
end
function DESOLVE_IVP(eq_lhs, eq_rhs, yname, t, y0)
    # desolve([y'=rhs(y), y(0)=y0], t, y); a one-element list is unwrapped
    rhs = string(eq_rhs(giac_eval(yname)))
    r = giac_eval("desolve([" * yname * "'=" * rhs * "," * yname * "(0)=" * string(y0) * "]," * string(t) * "," * yname * ")")
    v = elements(r)
    length(v) == 1 ? v[1] : r
end
LAPLACE(f, t, s) = cmd(:laplace, f, t, s)
ILAPLACE(F, s, t) = cmd(:ilaplace, F, s, t)
LIMIT(f, x, x0) = cmd(:limit, f, x, gx(x0))
SERIES(f, x, n) = giac_eval("convert(series(" * string(f) * "," * string(x) * ",0," * string(n) * "),polynom)")
GCD(p, q) = cmd(:gcd, p, q)
RESULTANT(p, q, x) = cmd(:resultant, p, q, x)
DISCRIMINANT(p, x) = cmd(:discriminant, p, x)
GROEBNER(polys, vars) = elements(cmd(:gbasis, cmd(:makevector, polys...), cmd(:makevector, vars...)))
DET(rows) = det(GiacMatrix(rows))
EIGENVALS(rows) = elements(cmd(:eigenvals, GiacMatrix(rows)))
ZTRANS(f, n, z) = cmd(:ztrans, f, n, z)
SUM(f, k, lo, hi) = cmd(:sum, f, k, gx(lo), gx(hi))
IFACTOR(nn) = to_julia(cmd(:ifactors, gx(nn)))
function ASSUME_SIMPLIFY(expr, x)
    giac_eval("assume(" * string(x) * ">0)")
    r = cmd(:simplify, expr)
    cmd(:purge, x)
    r
end
TRIGSIMP(f) = cmd(:simplify, f)
PARTFRAC(f, x) = cmd(:partfrac, f, x)
CFACTOR(f) = cmd(:cfactor, f)

# reduced Gröbner basis (degrevlex) of polynomials given as strings; p == 0 for Q, else GF(p)
function GROEBNER(polys::Vector{String}, vars::Vector{String}, p::Int)
    L = "[" * replace(join(polys, ","), "//" => "/") * "]"   # Giac writes rationals with one slash
    V = "[" * join(vars, ",") * "]"
    r = giac_eval(p == 0 ? "gbasis($L,$V,revlex)" : "gbasis($L % $p,$V,revlex)")
    [replace(string(e), r" % -?\d+" => "") for e in elements(r)]
end

const OPS = Dict{Symbol,Any}(
    :groebner => GROEBNER,
    :integrate_text => INTEGRATE_TEXT,
    :expand => f -> cmd(:expand, f),
    :factor => FACTOR,
    :integrate => (f, x) -> cmd(:integrate, f, x),
    :simplify => f -> cmd(:simplify, f),
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
    :ztrans => ZTRANS,
    :sum => SUM,
    :ifactor => IFACTOR,
    :assume_simplify => ASSUME_SIMPLIFY,
    :trigsimp => TRIGSIMP,
    :cfactor => CFACTOR,
)

function UNSOLVED(op, out)
    s = string(out)
    s == "[]" && return true
    occursin("Unable to solve", s) && return true
    s == "undef" && return true
    any(w -> occursin(w, s), ("integrate(", "integral(", "sum(", "product(", "limit(", "desolve(", "laplace(", "ilaplace(", "ztrans(")) && return true
    false
end

function EVAL(ex, vals)
    ex isa Number && return ex
    ex isa GiacExpr || return nothing
    d = Dict{GiacExpr,Any}(VAR[v] => r12(p) for (v, p) in vals if haskey(VAR, v))
    u = to_julia(cmd(:evalf, isempty(d) ? ex : Giac.substitute(ex, d)))
    u isa Number ? u : nothing
end
NTERMS(ex) = ex isa GiacExpr && string(cmd(:sommet, ex)) == "'+'" ? toint(cmd(:nops, ex)) : 1
NFACTORS(ex) = ex isa GiacExpr && string(cmd(:sommet, ex)) == "'*'" ? toint(cmd(:nops, ex)) : 1
IS_EXACT(ex) = occursin("pi", string(ex)) && !occursin(r"\d\.\d", string(ex))
CLEARCACHE() = nothing
VERSIONS() = ["Giac.jl" => string(pkgversion(Giac)),
              "GIAC_jll" => string(pkgversion(Giac.GIAC_jll)),
              "libgiac_julia_jll" => string(pkgversion(Giac.libgiac_julia_jll)),
              "giac_version" => string(giac_eval("version()"))]
