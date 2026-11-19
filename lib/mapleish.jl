# The Maple-like syntax of the 12000.org test files (bench F): translation to
# the input syntax of each system, numeric evaluation in plain Julia (the
# system-neutral side of the check), and a leaf count (the size measure of
# the A/B grades of those tests).
#
# The test files write `^`, `sqrt`, `exp`, `log`/`ln`, `arctan`, `arcsinh`,
# `Pi`, `I`, `GAMMA`, `polylog(n,z)`, `EllipticF(z,m)`, `hypergeom([..],[..],z)`.
# Free symbols are single letters (a, b, c, d, e, f, g, h, m, n, p, q, ...,
# A, B, C, D, F) and the variable is x; `e` is a symbol, not Euler's number.

module Mapleish

export translate, leaf_count, julia_expr, make_evaluator

# function renames per dialect; a function absent from a dialect's table keeps its name
const JULIA = Dict("arctan" => "atan", "arcsin" => "asin", "arccos" => "acos", "arccot" => "acot", "arcsec" => "asec",
                   "arccsc" => "acsc", "arctanh" => "atanh", "arcsinh" => "asinh", "arccosh" => "acosh", "arccoth" => "acoth",
                   "arcsech" => "asech", "arccsch" => "acsch", "ln" => "log", "GAMMA" => "gamma", "Zeta" => "zeta",
                   "Ei" => "expinti", "Si" => "sinint", "Ci" => "cosint", "erf" => "erf", "erfc" => "erfc", "erfi" => "erfi",
                   "LambertW" => "lambertw", "Shi" => "sinhint", "Chi" => "coshint")
const GIAC = Dict("arctan" => "atan", "arcsin" => "asin", "arccos" => "acos", "arccot" => "acot", "arcsec" => "asec",
                  "arccsc" => "acsc", "arctanh" => "atanh", "arcsinh" => "asinh", "arccosh" => "acosh", "arccoth" => "acoth",
                  "arcsech" => "asech", "arccsch" => "acsch", "log" => "ln", "GAMMA" => "Gamma", "polylog" => "polylog",
                  "LambertW" => "LambertW", "Ei" => "Ei", "Si" => "Si", "Ci" => "Ci")
const SYMPY = Dict("arctan" => "atan", "arcsin" => "asin", "arccos" => "acos", "arccot" => "acot", "arcsec" => "asec",
                   "arccsc" => "acsc", "arctanh" => "atanh", "arcsinh" => "asinh", "arccosh" => "acosh", "arccoth" => "acoth",
                   "arcsech" => "asech", "arccsch" => "acsch", "ln" => "log", "GAMMA" => "gamma", "Zeta" => "zeta",
                   "FresnelC" => "fresnelc", "FresnelS" => "fresnels", "EllipticF" => "elliptic_f", "EllipticE" => "elliptic_e",
                   "EllipticPi" => "elliptic_pi", "hypergeom" => "hyper")
const MAXIMA = Dict("arctan" => "atan", "arcsin" => "asin", "arccos" => "acos", "arccot" => "acot", "arcsec" => "asec",
                    "arccsc" => "acsc", "arctanh" => "atanh", "arcsinh" => "asinh", "arccosh" => "acosh", "arccoth" => "acoth",
                    "arcsech" => "asech", "arccsch" => "acsch", "ln" => "log", "GAMMA" => "gamma", "Zeta" => "zeta",
                    "Ei" => "expintegral_ei", "Si" => "expintegral_si", "Ci" => "expintegral_ci", "Shi" => "expintegral_shi",
                    "Chi" => "expintegral_chi", "LambertW" => "lambert_w", "polylog" => "li")
const FRICAS = Dict("arctan" => "atan", "arcsin" => "asin", "arccos" => "acos", "arccot" => "acot", "arcsec" => "asec",
                    "arccsc" => "acsc", "arctanh" => "atanh", "arcsinh" => "asinh", "arccosh" => "acosh", "arccoth" => "acoth",
                    "arcsech" => "asech", "arccsch" => "acsch", "ln" => "log", "GAMMA" => "Gamma", "Ei" => "Ei", "Si" => "Si",
                    "Ci" => "Ci", "Shi" => "Shi", "Chi" => "Chi", "polylog" => "polylog", "erf" => "erf", "erfi" => "erfi")
const SAGE = Dict("ln" => "log", "GAMMA" => "gamma", "Zeta" => "zeta", "Ei" => "Ei", "Si" => "sin_integral", "Ci" => "cos_integral",
                  "Shi" => "sinh_integral", "Chi" => "cosh_integral", "LambertW" => "lambert_w", "FresnelC" => "fresnel_cos",
                  "FresnelS" => "fresnel_sin", "EllipticF" => "elliptic_f", "EllipticE" => "elliptic_e", "EllipticPi" => "elliptic_pi",
                  "hypergeom" => "hypergeometric", "polylog" => "polylog")
const TABLES = Dict(:julia => JULIA, :giac => GIAC, :sympy => SYMPY, :maxima => MAXIMA, :fricas => FRICAS, :sage => SAGE)
# constants per dialect
const CONSTS = Dict(:julia => Dict("Pi" => "pi", "I" => "im"), :giac => Dict("Pi" => "pi", "I" => "i"),
                    :sympy => Dict("Pi" => "pi", "I" => "I"), :maxima => Dict("Pi" => "%pi", "I" => "%i"),
                    :fricas => Dict("Pi" => "%pi", "I" => "%i"), :sage => Dict("Pi" => "pi", "I" => "I"))
# functions the test files use whose meaning is not a plain function call (abstract functions, held forms)
const UNSUPPORTED = ("Derivative", "Unintegrable", "CannotIntegrate", "RootSum", "AppellF1", "HypergeometricPFQ", "f", "g")

"""
    translate(s, dialect) -> String

Rewrite a Maple-like expression for `dialect` (:julia, :giac, :sympy, :maxima,
:fricas): function names and constants from the tables, `^` kept except for
:sympy (`**`). Throws on an unsupported function.
"""
function translate(s::AbstractString, dialect::Symbol)
    tbl, consts = TABLES[dialect], CONSTS[dialect]
    out = IOBuffer()
    i = firstindex(s); n = lastindex(s)
    while i <= n
        c = s[i]
        if isletter(c) || c == '_'
            j = i
            while j <= n && (isletter(s[j]) || isdigit(s[j]) || s[j] == '_'); j = nextind(s, j); end
            id = s[i:prevind(s, j)]
            # a function call?
            k = j
            while k <= n && isspace(s[k]); k = nextind(s, k); end
            iscall = k <= n && s[k] == '('
            if iscall
                id in UNSUPPORTED && error("unsupported function $id")
                print(out, get(tbl, id, id))
            else
                print(out, get(consts, id, id))
            end
            i = j
        elseif c == '^' && dialect == :sympy
            print(out, "**"); i = nextind(s, i)
        else
            print(out, c); i = nextind(s, i)
        end
    end
    String(take!(out))
end

"""
    leaf_count(s) -> Int

Number of leaves of a printed expression: numbers and identifiers, counting a
function name as a leaf (the leaf count of the 12000.org grading, roughly).
"""
leaf_count(s::AbstractString) = count(_ -> true, eachmatch(r"[A-Za-z_][A-Za-z_0-9]*|\d+(?:\.\d+)?", s))

"""
    julia_expr(s) -> Expr

The Maple-like expression parsed as a Julia expression (after `translate(s, :julia)`).
"""
julia_expr(s::AbstractString) = Meta.parse(translate(s, :julia))

# ---------------------------------------------------------------------------
# plain-Julia evaluation at a point (complex arithmetic, so that square roots
# and logarithms of negative values are defined)
# ---------------------------------------------------------------------------
module Fns
    using SpecialFunctions: gamma, zeta, erf, erfc, erfi, expinti, sinint, cosint
    # functions Base lacks or whose real version throws on the complex plane
    sinhint(z) = error("Shi: not evaluated")
    coshint(z) = error("Chi: not evaluated")
    lambertw(z) = error("LambertW: not evaluated")
    polylog(n, z) = error("polylog: not evaluated")
    FresnelC(z) = error("FresnelC: not evaluated")
    FresnelS(z) = error("FresnelS: not evaluated")
    EllipticF(z, m) = error("EllipticF: not evaluated")
    EllipticE(z, m) = error("EllipticE: not evaluated")
    EllipticPi(z, n, m) = error("EllipticPi: not evaluated")
    hypergeom(a, b, z) = error("hypergeom: not evaluated")
    Li(z) = error("Li: not evaluated")
    Psi(z) = error("Psi: not evaluated")
    lnGAMMA(z) = error("lnGAMMA: not evaluated")
end

"""
    make_evaluator(s, names) -> f

A function `f(point::Dict{Symbol,Float64}) -> ComplexF64` evaluating the
Maple-like expression `s` with every symbol of `names` bound to its complex
value at the point. Compiled once per expression (a closure over a generated
function); throws at evaluation if a function is not available.
"""
function make_evaluator(s::AbstractString, names::Vector{Symbol})
    ex = julia_expr(s)
    args = Expr(:tuple, names...)
    fn = Core.eval(Fns, Expr(:->, args, ex))
    Base.invokelatest(() -> nothing)
    pt -> Base.invokelatest(fn, (ComplexF64(pt[nm]) for nm in names)...)
end

end # module
