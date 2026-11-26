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
                   "LambertW" => "lambertw", "Shi" => "sinhint", "Chi" => "coshint",
                   "HurwitzZeta" => "zeta", "ExpIntegralE" => "expint")
const GIAC = Dict("arctan" => "atan", "arcsin" => "asin", "arccos" => "acos", "arccot" => "acot", "arcsec" => "asec",
                  "arccsc" => "acsc", "arctanh" => "atanh", "arcsinh" => "asinh", "arccosh" => "acosh", "arccoth" => "acoth",
                  "arcsech" => "asech", "arccsch" => "acsch", "log" => "ln", "GAMMA" => "Gamma", "polylog" => "polylog",
                  "LambertW" => "LambertW", "Ei" => "Ei", "Si" => "Si", "Ci" => "Ci")
const SYMPY = Dict("arctan" => "atan", "arcsin" => "asin", "arccos" => "acos", "arccot" => "acot", "arcsec" => "asec",
                   "arccsc" => "acsc", "arctanh" => "atanh", "arcsinh" => "asinh", "arccosh" => "acosh", "arccoth" => "acoth",
                   "arcsech" => "asech", "arccsch" => "acsch", "ln" => "log", "GAMMA" => "gamma", "Zeta" => "zeta",
                   "FresnelC" => "fresnelc", "FresnelS" => "fresnels", "EllipticF" => "elliptic_f", "EllipticE" => "elliptic_e",
                   "EllipticPi" => "elliptic_pi", "hypergeom" => "hyper", "HurwitzZeta" => "zeta", "ExpIntegralE" => "expint")
const MAXIMA = Dict("arctan" => "atan", "arcsin" => "asin", "arccos" => "acos", "arccot" => "acot", "arcsec" => "asec",
                    "arccsc" => "acsc", "arctanh" => "atanh", "arcsinh" => "asinh", "arccosh" => "acosh", "arccoth" => "acoth",
                    "arcsech" => "asech", "arccsch" => "acsch", "ln" => "log", "GAMMA" => "gamma", "Zeta" => "zeta",
                    "Ei" => "expintegral_ei", "Si" => "expintegral_si", "Ci" => "expintegral_ci", "Shi" => "expintegral_shi",
                    "Chi" => "expintegral_chi", "LambertW" => "lambert_w", "polylog" => "li", "ExpIntegralE" => "expintegral_e")
const FRICAS = Dict("arctan" => "atan", "arcsin" => "asin", "arccos" => "acos", "arccot" => "acot", "arcsec" => "asec",
                    "arccsc" => "acsc", "arctanh" => "atanh", "arcsinh" => "asinh", "arccosh" => "acosh", "arccoth" => "acoth",
                    "arcsech" => "asech", "arccsch" => "acsch", "ln" => "log", "GAMMA" => "Gamma", "Ei" => "Ei", "Si" => "Si",
                    "Ci" => "Ci", "Shi" => "Shi", "Chi" => "Chi", "polylog" => "polylog", "erf" => "erf", "erfi" => "erfi")
const SAGE = Dict("ln" => "log", "GAMMA" => "gamma", "Zeta" => "zeta", "Ei" => "Ei", "Si" => "sin_integral", "Ci" => "cos_integral",
                  "Shi" => "sinh_integral", "Chi" => "cosh_integral", "LambertW" => "lambert_w", "FresnelC" => "fresnel_cos",
                  "FresnelS" => "fresnel_sin", "EllipticF" => "elliptic_f", "EllipticE" => "elliptic_e", "EllipticPi" => "elliptic_pi",
                  "hypergeom" => "hypergeometric", "polylog" => "polylog", "HurwitzZeta" => "hurwitz_zeta",
                  "ExpIntegralE" => "exp_integral_e")
const TABLES = Dict(:julia => JULIA, :giac => GIAC, :sympy => SYMPY, :maxima => MAXIMA, :fricas => FRICAS, :sage => SAGE)
# constants per dialect
const CONSTS = Dict(:julia => Dict("Pi" => "pi", "I" => "im"), :giac => Dict("Pi" => "pi", "I" => "i"),
                    :sympy => Dict("Pi" => "pi", "I" => "I"), :maxima => Dict("Pi" => "%pi", "I" => "%i"),
                    :fricas => Dict("Pi" => "%pi", "I" => "%i"), :sage => Dict("Pi" => "pi", "I" => "I"))
# functions the test files use whose meaning is not a plain function call (abstract functions, held forms)
const UNSUPPORTED = ("Derivative", "Unintegrable", "CannotIntegrate", "RootSum", "AppellF1", "HypergeometricPFQ", "f", "g",
                     "ZetaDerivative")
# Maple's multi-argument forms, rewritten by arity before the renames (see rewrite_arity): Zeta(0,s,a) is the Hurwitz
# zeta function and Ei(n,z) the generalized exponential integral E_n(z). Each target was checked numerically in the
# system on 2026-11-26 (zeta(2,1.7) = 0.793232830163998, E_2(0.6) = 0.276183934180385); a system without the
# function gets no translation: Giac's two-argument Zeta is not Hurwitz's, Maxima has no Hurwitz zeta, FriCAS
# has neither. Giac's E_n is Ei(z,n), its arguments in the other order. Before 2026-11-26 these forms were
# passed with Maple's arguments and every system rejected or misread them (bench F cases 616, 617, 628 to 630).
const NO_TRANSLATION = Dict(:giac => ("HurwitzZeta",), :maxima => ("HurwitzZeta",), :fricas => ("HurwitzZeta", "ExpIntegralE"))

# the arguments of the call whose opening parenthesis is at index `open`, and the index of its closing one
function call_args(s::AbstractString, open::Int)
    depth = 0; args = String[]; start = nextind(s, open); i = open
    while true
        i = nextind(s, i)
        i > lastindex(s) && error("unbalanced parentheses in $s")
        c = s[i]
        if c in ('(', '[')
            depth += 1
        elseif c in (')', ']')
            if depth == 0
                push!(args, strip(s[start:prevind(s, i)]))
                return args, i
            end
            depth -= 1
        elseif c == ',' && depth == 0
            push!(args, strip(s[start:prevind(s, i)])); start = nextind(s, i)
        end
    end
end

"""
    rewrite_arity(s, dialect) -> String

Maple's Zeta(n, s, a) and Ei(n, z) as HurwitzZeta(s, a) (n = 0), ZetaDerivative (n > 0, unsupported) and
ExpIntegralE(n, z), or Ei(z, n) for Giac; the one-argument forms are kept.
"""
function rewrite_arity(s::AbstractString, dialect::Symbol)
    out = IOBuffer(); i = firstindex(s)
    while i <= lastindex(s)
        m = match(r"\b(Zeta|Ei)\s*\(", s, i)
        m === nothing && (print(out, s[i:end]); break)
        open = m.offset + length(m.match) - 1
        args, close = call_args(s, open)
        args = [rewrite_arity(a, dialect) for a in args]
        print(out, s[i:prevind(s, m.offset)])
        if m[1] == "Zeta" && length(args) == 3
            print(out, args[1] == "0" ? "HurwitzZeta($(args[2]),$(args[3]))" : "ZetaDerivative($(join(args, ",")))")
        elseif m[1] == "Ei" && length(args) == 2
            print(out, dialect == :giac ? "Ei($(args[2]),$(args[1]))" : "ExpIntegralE($(args[1]),$(args[2]))")
        else
            print(out, m[1], "(", join(args, ","), ")")
        end
        i = nextind(s, close)
    end
    String(take!(out))
end

"""
    translate(s, dialect) -> String

Rewrite a Maple-like expression for `dialect` (:julia, :giac, :sympy, :maxima,
:fricas): function names and constants from the tables, `^` kept except for
:sympy (`**`). Throws on an unsupported function.
"""
function translate(s::AbstractString, dialect::Symbol)
    tbl, consts = TABLES[dialect], CONSTS[dialect]
    occursin(r"\b(Zeta|Ei)\s*\(", s) && (s = rewrite_arity(s, dialect))
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
                id in get(NO_TRANSLATION, dialect, ()) && error("unsupported function $id: no translation for this system")
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
    # a zero imaginary part made +0.0 after every operation of an evaluated expression: Julia's complex arithmetic gives
    # -0.0 (cos(2.53 + 0.0im) is -0.819 - 0.0im, -(1.7 + 0.0im) is -1.7 - 0.0im), which puts a power or a root of a
    # negative real on the other side of its cut; +0.0 gives the principal value every system gives (test/integration_cuts.jl)
    _cz(z::Complex) = complex(real(z), imag(z) + 0.0)
    _cz(z) = z
    using SpecialFunctions: gamma, zeta, erf, erfc, erfi, expinti, expint, sinint, cosint
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
    # residual integral of an OSR replacement, int(lambda t. H)(x): numeric quadrature from a fixed base point
    # (the comparison with a certified antiderivative is up to a constant, so the base point does not matter)
    const OSR_BASE = 0.31
    function osr_int(f, x)
        simpson(a, b, fa, fm, fb, whole, depth) = begin
            m = (a + b) / 2; lm = (a + m) / 2; rm = (m + b) / 2
            flm, frm = f(lm), f(rm)
            left = (m - a) / 6 * (fa + 4flm + fm); right = (b - m) / 6 * (fm + 4frm + fb)
            (depth <= 0 || abs(left + right - whole) <= 1e-10 * max(1.0, abs(left + right))) && return left + right + (left + right - whole) / 15
            simpson(a, m, fa, flm, fm, left, depth - 1) + simpson(m, b, fm, frm, fb, right, depth - 1)
        end
        a, b = ComplexF64(OSR_BASE), ComplexF64(x)
        a == b && return zero(ComplexF64)
        fa, fb, fm = f(a), f(b), f((a + b) / 2)
        simpson(a, b, fa, fm, fb, (b - a) / 6 * (fa + 4fm + fb), 40)
    end
end

"""
    make_evaluator(s, names) -> f

A function `f(point::Dict{Symbol,Float64}) -> ComplexF64` evaluating the
Maple-like expression `s` with every symbol of `names` bound to its complex
value at the point. Compiled once per expression (a closure over a generated
function); throws at evaluation if a function is not available.
"""
canonical_zeros(ex) = ex isa Expr && ex.head === :call ?
    Expr(:call, :_cz, Expr(:call, ex.args[1], map(canonical_zeros, ex.args[2:end])...)) : ex

function make_evaluator(s::AbstractString, names::Vector{Symbol})
    ex = canonical_zeros(julia_expr(s))
    args = Expr(:tuple, names...)
    fn = Core.eval(Fns, Expr(:->, args, ex))
    Base.invokelatest(() -> nothing)
    pt -> Base.invokelatest(fn, (ComplexF64(pt[nm]) for nm in names)...)
end

end # module
