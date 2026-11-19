# Bench E: the 103 problems of "Giac.jl against Mathematica", the notebook
# `notebooks/giac_vs_wolfram.jl` of the `ergonomics` branch of Kahli Burke's
# fork of Giac.jl (github.com/kahliburke/Giac.jl, commit da3d2f1a, 2026-11-12),
# with the problem statements taken from that notebook, plus a "model to
# Jacobian" category in the style of its companion `notebooks/cas_comparison.jl`.
#
# What differs from the notebook: Mathematica is not run; the systems are
# Giac.jl as released upstream (none of the fork's Julia-side layers: no Nemo
# algebraic simplifier, msolve, sum-of-squares, Struve/Kovacic/elliptic code),
# SymPy through SymPyPythonCall, Symbolics.jl and SymJ.jl; and every check is
# written here in plain Julia, system-neutral, with the notebook's criteria: a
# value to a tolerance, an antiderivative by its derivative at points,
# solutions substituted and counted, differential equations by the residual
# with the constants given values, regions tested at points inside and
# outside, and for some problems a form (denested, no trigonometric function
# left, a number of factors).
#
# Statuses: verified (passes), unsolved (returned unevaluated, numeric where
# exact was asked, or not in the form asked), wrong (fails), unverified (the
# check could not evaluate the answer), unavailable (no such operation),
# error, timeout. A task returns the answer, or (answer, post) with post() an
# auxiliary computation (a residual) done outside the timed call.

using .BenchCommon: numeq
using LinearAlgebra: diag, Diagonal, I

# ---------------------------------------------------------------------------
# reference values in plain Julia
# ---------------------------------------------------------------------------
const γe = Float64(Base.MathConstants.eulergamma)
const ZETA3 = 1.2020569031595942853997
function erf_ref(x)
    s = big(0.0); term = big(x); n = 0
    while abs(term) > big(1e-40) && n < 400
        s += term / (2n + 1); n += 1
        term *= -big(x)^2 / n
    end
    Float64(2 / sqrt(big(pi)) * s)
end
function J0_ref(x)
    s = big(0.0); term = big(1.0); m = 0
    while abs(term) > big(1e-40) && m < 400
        s += term; m += 1
        term *= -(big(x) / 2)^2 / m^2
    end
    Float64(s)
end
function agm(a, b)
    for _ in 1:60
        a, b = (a + b) / 2, sqrt(a * b)
    end
    a
end
ellipK_m(m) = pi / (2 * agm(1.0, sqrt(1 - m)))        # complete elliptic integral, parameter m
function lambertw_ref(x)
    w = log(1 + x)
    for _ in 1:60
        w -= (w * exp(w) - x) / (exp(w) * (w + 1))
    end
    w
end

# ---------------------------------------------------------------------------
# generic checks
# ---------------------------------------------------------------------------
unwrap_post(out) = out isa Tuple && length(out) == 2 && out[2] isa Function ? (out[1], out[2]()) : (out, nothing)
# a plain number: not a symbolic wrapper such as SymPy's Sym (which is a Julia Number)
isplain(v) = v isa Union{AbstractFloat, Integer, Rational, AbstractIrrational} && !(v isa Bool) || (v isa Complex && isplain(real(v)))
tonum(v) = isplain(v) ? Float64(real(v)) : nothing
hasfloat(s) = occursin(r"\d\.\d", s)

function check_value(out, ref; at = Dict{Symbol,Float64}(), rtol = 1e-9, atol = 1e-12)
    v = isplain(out) ? tonum(out) : tonum(EVAL(out, at))
    v === nothing && return :unverified
    isfinite(v) || return :wrong
    numeq(v, ref; rtol, atol) ? :verified : :wrong
end
# the notebook's Value: to twelve digits, and the answer must be exact
function check_exact_value(out, ref; at = Dict{Symbol,Float64}(), rtol = 1e-9)
    st = check_value(out, ref; at, rtol)
    st === :verified && hasfloat(string(out)) ? :unsolved : st
end
function check_antiderivative(out, f; pts = (0.31, 0.57, 1.23), h = 1e-5, rtol = 1e-5)
    replace(string(out), " " => "") in ("infinity", "-infinity", "undef") && return :wrong
    for x0 in pts
        fp = tonum(EVAL(out, Dict(:x => x0 + h))); fm = tonum(EVAL(out, Dict(:x => x0 - h)))
        (fp === nothing || fm === nothing) && return :unverified
        numeq((fp - fm) / (2h), f(x0); rtol, atol = 1e-7) || return :wrong
    end
    :verified
end
# the residuals of an ODE answer (a list: the equation, then the conditions), with the
# constants set, at points of the variable
function check_residual(out; var = :x, pts = (0.3, 0.7, 1.1), extra = Dict{Symbol,Float64}(), atol = 1e-6)
    sol, res = unwrap_post(out)
    res === nothing && return :unverified
    for r in (res isa AbstractVector ? res : [res])
        for p in pts
            v = tonum(EVAL(r, merge(extra, Dict(var => p))))
            v === nothing && return :unverified
            abs(v) <= atol || return :wrong
        end
    end
    :verified
end
# a list of solutions (tuples of numbers) must have `count` elements, each a zero of F
function check_solutions(out, F::Function, count::Int)
    out isa AbstractVector || return :unverified
    length(out) == count || return length(out) < count ? :unsolved : :wrong
    for v in out
        vv = v isa Tuple ? collect(v) : [v]
        # an exact answer written with Lambert's W is evaluated here
        vv = [(m = match(r"^(?:lambertw|LambertW)\((\d+)\)$", replace(string(e), " " => "")); m === nothing ? e : lambertw_ref(parse(Float64, m[1]))) for e in vv]
        vv = [e isa Number ? e : tonum(EVAL(e, Dict{Symbol,Float64}())) for e in vv]
        all(x -> x isa Number, vv) || return :unverified
        all(abs.(F(vv...)) .< 1e-6) || return :wrong
    end
    :verified
end
function check_intervals(out, inside::Vector{Float64}, outside::Vector{Float64})
    s = replace(string(out), " " => "")
    ivs = Tuple{Float64,Float64}[]
    for m in eachmatch(r"Interval(?:\.open|\.Lopen|\.Ropen)?\(([-\d./]+),([-\d./]+)\)", s)
        push!(ivs, (evalnum(m[1]), evalnum(m[2])))
    end
    for m in eachmatch(r"\(?[a-z]>([-\d./]+)\)?and\(?[a-z]<([-\d./]+)\)?", s)
        push!(ivs, (evalnum(m[1]), evalnum(m[2])))
    end
    for m in eachmatch(r"([-\d./]+)<[a-z]<([-\d./]+)", s)
        push!(ivs, (evalnum(m[1]), evalnum(m[2])))
    end
    for m in eachmatch(r"\(?([-\d./]+)<[a-z]\)?&\(?[a-z]<([-\d./]+)\)?", s)
        push!(ivs, (evalnum(m[1]), evalnum(m[2])))
    end
    isempty(ivs) && for m in eachmatch(r"\(([-\d./]+),([-\d./]+)\)", s)     # (a, b) ∪ (c, d)
        push!(ivs, (evalnum(m[1]), evalnum(m[2])))
    end
    isempty(ivs) && return :unverified
    inset(v) = any(((a, b),) -> a < v < b, ivs)
    (all(inset, inside) && !any(inset, outside)) ? :verified : :wrong
end
evalnum(s) = occursin('/', s) ? (p = split(s, '/'); parse(Float64, p[1]) / parse(Float64, p[2])) : parse(Float64, s)
# (unit, [(factor, multiplicity)]) with the expected number of non-constant factors
function check_factors(out, ref, nfactors, pt::Dict{Symbol,Float64})
    out isa Tuple && length(out) == 2 || return :unverified
    unit, fs = out
    length(fs) == nfactors || return length(fs) < nfactors ? :unsolved : :wrong
    p = isplain(unit) ? tonum(unit) : tonum(EVAL(unit, pt))
    p === nothing && return :unverified
    for (g, m) in fs
        v = tonum(EVAL(g, pt))
        v === nothing && return :unverified
        p *= v^m
    end
    numeq(p, ref; rtol = 1e-8) ? :verified : :wrong
end
function nested_radicals(s::AbstractString)
    depth = 0; maxd = 0; stack = Bool[]
    i = 1
    while i <= lastindex(s)
        if startswith(SubString(s, i), "sqrt(") || startswith(SubString(s, i), "root(") || startswith(SubString(s, i), "cbrt(")
            push!(stack, true); depth += 1; maxd = max(maxd, depth)
            i += findfirst('(', SubString(s, i))
            continue
        elseif s[i] == '('
            push!(stack, false)
        elseif s[i] == ')' && !isempty(stack)
            pop!(stack) && (depth -= 1)
        end
        i = nextind(s, i)
    end
    maxd > 1 || occursin(r"\^\(1/\d\)[^\^]*\^\(1/\d\)", s)
end
# a form: the value must pass, then the printed answer must satisfy `form`
check_form(out, value_status::Symbol, form::Bool) = value_status === :verified ? (form ? :verified : :unsolved) : value_status
notrig(s) = !occursin(r"\b(cos|sin|tan|acos|asin|atan)\b", s)
function check_bool(out, expected)
    s = lowercase(replace(string(out), " " => ""))
    s in ("true", "1") && return expected ? :verified : :wrong
    s in ("false", "0") && return expected ? :wrong : :verified
    :unverified
end
asbig(v) = v isa Integer ? big(v) : (try parse(BigInt, replace(string(v), " " => "")) catch; nothing end)
check_integer(out, expected) = (v = asbig(out); v === nothing ? :unverified : (v == big(expected) ? :verified : :wrong))
matrix_of(out) = out isa AbstractMatrix ? (try Float64.(real.(out)) catch; nothing end) : nothing
function check_matrix(out, ref::AbstractMatrix; rtol = 1e-8)
    M = matrix_of(out)
    M === nothing && return :unverified
    size(M) == size(ref) || return :wrong
    all(numeq.(M, ref; rtol, atol = 1e-10)) ? :verified : :wrong
end
function check_vector(out, ref::AbstractVector; rtol = 1e-8, sorted = false)
    out isa AbstractVector || return :unverified
    vals = [tonum(o) for o in out]
    any(isnothing, vals) && return :unverified
    length(vals) == length(ref) || return :wrong
    a, b = sorted ? (sort(vals), sort(ref)) : (vals, ref)
    all(numeq.(a, b; rtol, atol = 1e-10)) ? :verified : :wrong
end

P(cat, name, check, note = "") = (name = name, op = Symbol(name), args = V -> (), check = check, note = note, category = cat)

const CAT = ["Indefinite integrals", "Definite integrals", "Sums and products", "Limits",
             "Equations and inequalities", "Polynomial algebra", "Simplification and algebraic numbers",
             "Differential equations", "Linear algebra", "Number theory", "Transforms and special functions",
             "Control", "Model to Jacobian"]

const PROBLEMS = [
    # ---- 1 Indefinite integrals ----
    P(CAT[1], "sqrt(tan x)", o -> check_antiderivative(o, x -> sqrt(tan(x))), "int sqrt(tan x) dx"),
    P(CAT[1], "Chebyshev's pseudo-elliptic integral", o -> check_antiderivative(o, x -> x / sqrt(x^4 + 10x^2 - 96x - 71); pts = (5.0, 6.0, 7.0)),
      "int x/sqrt(x^4+10x^2-96x-71) dx"),
    P(CAT[1], "An arctangent of a radical", o -> check_antiderivative(o, x -> (x^2 - 1) / ((x^2 + 1) * sqrt(x^4 + 1))),
      "int (x^2-1)/((x^2+1) sqrt(x^4+1)) dx"),
    P(CAT[1], "A quintic denominator", o -> check_antiderivative(o, x -> 1 / (x^5 - x + 1)), "int dx/(x^5-x+1)"),
    P(CAT[1], "A fourth root", o -> check_antiderivative(o, x -> 1 / (1 + x^4)^(1 / 4)), "int dx/(1+x^4)^(1/4)"),
    P(CAT[1], "Parts, twice", o -> check_antiderivative(o, x -> x^2 * asin(x)^2; pts = (-0.5, 0.3, 0.7)), "int x^2 asin(x)^2 dx"),
    P(CAT[1], "Exponential and logarithm (Risch)", o -> check_antiderivative(o, x -> exp(x) * (1 + x * log(x)) / x), "int e^x (1 + x ln x)/x dx"),
    P(CAT[1], "A Bessel function, to Struve functions", o -> check_antiderivative(o, x -> x^2 * J0_ref(x)), "int x^2 J0(x) dx"),
    P(CAT[1], "The error function squared", o -> check_antiderivative(o, x -> erf_ref(x)^2), "int erf(x)^2 dx"),
    # ---- 2 Definite integrals ----
    P(CAT[2], "Bose-Einstein type", o -> check_exact_value(o, pi^2 / 6), "int_0^inf x/(e^x-1) dx = pi^2/6"),
    P(CAT[2], "Serret's integral", o -> check_exact_value(o, pi / 8 * log(2)), "int_0^1 ln(1+x)/(1+x^2) dx = pi ln2/8"),
    P(CAT[2], "A symmetry trick", o -> check_exact_value(o, pi^2 / 4), "int_0^pi x sin x/(1+cos^2 x) dx = pi^2/4"),
    P(CAT[2], "Log-sine", o -> check_exact_value(o, -pi / 2 * log(2)), "int_0^(pi/2) ln sin x dx = -pi ln2/2"),
    P(CAT[2], "Ahmed's integral", o -> check_exact_value(o, 5pi^2 / 96), "int_0^1 atan(sqrt(x^2+2))/((x^2+1) sqrt(x^2+2)) dx = 5pi^2/96"),
    P(CAT[2], "Laplace's integral", o -> check_exact_value(o, pi / (2 * exp(1))), "int_0^inf cos x/(1+x^2) dx = pi/(2e)"),
    P(CAT[2], "A dilogarithm value", o -> check_exact_value(o, 2 - pi^2 / 6), "int_0^1 ln x ln(1-x) dx = 2 - pi^2/6"),
    P(CAT[2], "Euler's constant", o -> check_exact_value(o, γe^2 + pi^2 / 6), "int_0^inf e^-x ln^2 x dx = gamma^2 + pi^2/6"),
    P(CAT[2], "A Gaussian with a cosine", o -> check_exact_value(o, sqrt(pi) / exp(1)), "int_-inf^inf e^(-x^2) cos 2x dx = sqrt(pi)/e"),
    P(CAT[2], "Frullani's integral", o -> check_exact_value(o, log(2)), "int_0^inf (e^-x - e^-2x)/x dx = ln 2"),
    P(CAT[2], "The error function", o -> check_exact_value(o, (2 - sqrt(2)) / sqrt(pi)), "int_0^inf erfc(x)^2 dx = (2-sqrt2)/sqrt(pi)"),
    P(CAT[2], "A Bessel function on the half-line", o -> check_exact_value(o, 1.0), "int_0^inf J0(x) dx = 1"),
    P(CAT[2], "A damped Bessel function", o -> check_exact_value(o, 1 / sqrt(2)), "int_0^inf e^-x J0(x) dx = 1/sqrt2"),
    P(CAT[2], "A pendulum's period", o -> check_exact_value(o, sqrt(2) * ellipK_m(sin(0.5)^2); at = Dict(:a => 1.0)),
      "int_0^a dtheta/sqrt(cos theta - cos a) = sqrt2 K(sin^2(a/2)), checked at a = 1"),
    # ---- 3 Sums and products ----
    P(CAT[3], "zeta(4)", o -> check_exact_value(o, pi^4 / 90), "sum 1/n^4 = pi^4/90"),
    P(CAT[3], "Harmonic numbers", o -> check_exact_value(o, 2ZETA3), "sum H_n/n^2 = 2 zeta(3)"),
    P(CAT[3], "Dirichlet beta(3)", o -> check_exact_value(o, pi^3 / 32), "sum (-1)^n/(2n+1)^3 = pi^3/32"),
    P(CAT[3], "Arithmetic-geometric", o -> check_exact_value(o, 6.0), "sum n^2/2^n = 6"),
    P(CAT[3], "A central binomial series", o -> check_exact_value(o, pi^2 / 18), "sum 1/(n^2 binomial(2n,n)) = pi^2/18"),
    P(CAT[3], "Vandermonde's identity", o -> check_exact_value(o, 3432.0; at = Dict(:n => 7.0)), "sum_k binomial(n,k)^2 = binomial(2n,n), checked at n = 7"),
    P(CAT[3], "A closed form in n", o -> check_exact_value(o, 18434.0; at = Dict(:n => 10.0)), "sum_{k=1}^n k 2^k = (n-1) 2^(n+1) + 2, checked at n = 10"),
    P(CAT[3], "A polylogarithm value", o -> check_exact_value(o, pi^2 / 12 - log(2)^2 / 2), "sum x^n/n^2 at x = 1/2"),
    P(CAT[3], "A telescoping product", o -> check_exact_value(o, 0.5), "prod_{n>=2} (1 - 1/n^2) = 1/2"),
    P(CAT[3], "Wallis's product", o -> check_exact_value(o, pi / 2), "prod 4n^2/(4n^2-1) = pi/2"),
    # ---- 4 Limits ----
    P(CAT[4], "tan sin - sin tan", o -> check_exact_value(o, 1 / 30), "lim (tan sin x - sin tan x)/x^7 = 1/30"),
    P(CAT[4], "Stirling", o -> check_exact_value(o, exp(-1.0)), "lim (n!)^(1/n)/n = 1/e"),
    P(CAT[4], "A second-order term of e", o -> check_exact_value(o, -exp(1) / 2), "lim x((1+1/x)^x - e) = -e/2"),
    P(CAT[4], "Nested exponentials (Gruntz)", o -> check_exact_value(o, -1.0), "lim e^x (e^(1/x - e^-x) - e^(1/x)) = -1"),
    P(CAT[4], "Cancelling poles", o -> check_exact_value(o, -1 / 3), "lim (1/x^2 - 1/sin^2 x) = -1/3"),
    P(CAT[4], "A ratio of Gamma functions", o -> check_exact_value(o, 1.0), "lim Gamma(x+1/2)/(Gamma(x) sqrt x) = 1"),
    P(CAT[4], "A power of sinc", o -> check_exact_value(o, exp(-1 / 6)), "lim (sin x/x)^(1/x^2) = e^(-1/6)"),
    P(CAT[4], "A bounded oscillation", o -> check_exact_value(o, 1.0), "lim (x + sin x)/x, x -> inf"),
    # ---- 5 Equations and inequalities ----
    P(CAT[5], "A sextic system", o -> check_solutions(o, (x, y) -> (x^2 + y^2 - 1, x^3 - y), 6), "x^2+y^2 = 1, x^3 = y: all six complex solutions"),
    P(CAT[5], "A quintic solvable by radicals", o -> (st = check_solutions(o, x -> (x^5 - 5x + 12,), 5); st === :verified && occursin(r"rootof|CRootOf|RootOf|\d\.\d", string(o)) ? :unsolved : st),
      "x^5-5x+12 = 0, five roots in radicals"),
    P(CAT[5], "Every solution of cos x = 1/2", o -> check_periodic(o), "cos x = 1/2, all solutions: six of them in (-10, 10)"),
    P(CAT[5], "Lambert's W", o -> check_solutions(o, x -> (x * exp(x) - 2,), 1), "x e^x = 2"),
    P(CAT[5], "A symmetric system", o -> check_solutions(o, (x, y, z) -> (x + y + z - 6, x * y + y * z + z * x - 11, x * y * z - 6), 6),
      "x+y+z = 6, xy+yz+zx = 11, xyz = 6: six solutions"),
    P(CAT[5], "A quartic inequality", o -> check_intervals(o, [-1.5, 1.5, -1.9, 1.9], [-2.5, -0.5, 0.0, 0.5, 2.5]), "x^4-5x^2+4 < 0"),
    P(CAT[5], "Absolute values", o -> check_intervals(o, [-2.9, 0.0, 1.9], [-4.0, -3.1, 2.1, 3.0]), "|x-1| + |x+2| < 5"),
    P(CAT[5], "Quantifier elimination", o -> check_intervals(o, [-1.9, 0.0, 1.9], [-3.0, -2.1, 2.1, 3.0]), "for which b is x^2+bx+1 > 0 for every real x: -2 < b < 2"),
    # ---- 6 Polynomial algebra ----
    P(CAT[6], "Cyclotomic factors", o -> check_factors(o, 0.7^105 - 1, 8, Dict(:x => 0.7)), "factor x^105 - 1 over Q: 8 factors"),
    P(CAT[6], "A symmetric septic", o -> check_factors(o, (0.7 + 0.4 + 0.3)^7 - 0.7^7 - 0.4^7 - 0.3^7, 4, Dict(:x => 0.7, :y => 0.4, :z => 0.3)),
      "factor (x+y+z)^7 - x^7 - y^7 - z^7: 4 factors"),
    P(CAT[6], "Factoring over Q(sqrt 2)", o -> check_factors(o, 0.7^4 + 1, 2, Dict(:x => 0.7)), "factor x^4 + 1 over Q(sqrt 2): 2 factors"),
    P(CAT[6], "The cyclic-6 system", o -> check_integer(o, 156), "the number of complex solutions of cyclic-6 (156)"),
    P(CAT[6], "Implicitization", o -> begin
          z1 = tonum(EVAL(o, Dict(:x => -0.91, :y => -0.273))); z2 = tonum(EVAL(o, Dict(:x => -0.51, :y => -0.357))); nz = tonum(EVAL(o, Dict(:x => 0.5, :y => 0.5)))
          (z1 === nothing || z2 === nothing || nz === nothing) ? :unverified : (abs(z1) < 1e-8 && abs(z2) < 1e-8 && abs(nz) > 1e-6 ? :verified : :wrong)
      end, "eliminate t from x = t^2-1, y = t^3-t"),
    P(CAT[6], "Polynomial decomposition", o -> (o isa Tuple && length(o) == 2 ? (h = tonum(EVAL(o[2], Dict(:x => 0.7))); g = h === nothing ? nothing : tonum(EVAL(o[1], Dict(:x => h))); g === nothing ? :unverified : (numeq(g, 0.7^6 + 6 * 0.7^4 + 0.7^3 + 9 * 0.7^2 + 3 * 0.7 - 5; rtol = 1e-8) ? :verified : :wrong)) : :unverified),
      "x^6+6x^4+x^3+9x^2+3x-5 = g(h(x))"),
    # ---- 7 Simplification and algebraic numbers ----
    P(CAT[7], "Denesting", o -> check_form(o, check_value(o, sqrt(2) + sqrt(3)), !nested_radicals(string(o))), "sqrt(5+2 sqrt 6) = sqrt2 + sqrt3"),
    P(CAT[7], "Ramanujan's denesting", o -> check_form(o, check_value(o, cbrt(cbrt(2) - 1)), !nested_radicals(string(o))), "cbrt(cbrt 2 - 1) = cbrt(1/9) - cbrt(2/9) + cbrt(4/9)"),
    P(CAT[7], "A heptagon sum", o -> check_form(o, check_value(o, -0.5), notrig(string(o))), "cos(2pi/7)+cos(4pi/7)+cos(6pi/7) = -1/2, no cosine left"),
    P(CAT[7], "A minimal polynomial", o -> check_value(o, 0.7^8 - 40 * 0.7^6 + 352 * 0.7^4 - 960 * 0.7^2 + 576; at = Dict(:x => 0.7)), "minimal polynomial of sqrt2+sqrt3+sqrt5, checked at x = 0.7"),
    P(CAT[7], "A trigonometric identity", o -> check_form(o, check_value(o, 2.0; at = Dict(:x => 0.7)), !occursin("x", string(o))), "sin 3x/sin x - cos 3x/cos x = 2"),
    P(CAT[7], "Gauss's 17-gon", o -> check_form(o, check_value(o, cos(2pi / 17)), notrig(string(o))), "cos(2pi/17) in square roots"),
    P(CAT[7], "An inverse cosine, with assumptions", o -> check_form(o, check_value(o, 2pi - 4; at = Dict(:x => 4.0)), notrig(string(o))), "acos(cos x) = 2pi - x for pi < x < 2pi"),
    # ---- 8 Differential equations ----
    P(CAT[8], "Airy", o -> check_residual(o), "y'' = x y"),
    P(CAT[8], "Bessel, order 1/2", o -> check_residual(o), "x^2 y'' + x y' + (x^2 - 1/4) y = 0"),
    P(CAT[8], "Riccati", o -> check_residual(o), "y' = x^2 + y^2"),
    P(CAT[8], "A nonlinear autonomous equation", o -> check_residual(o), "y y'' = y'^2"),
    P(CAT[8], "A forced Euler-Cauchy equation", o -> check_residual(o), "x^2 y'' - 3x y' + 4y = x^2 ln x"),
    P(CAT[8], "Bernoulli", o -> check_residual(o), "y' + y = x y^3"),
    P(CAT[8], "An exponential solution (Kovacic)", o -> check_residual(o), "y'' = (x^2+1) y"),
    P(CAT[8], "A forced initial-value problem", o -> check_residual(o), "y'' - (x^2+1) y = x e^(-x^2/2), y(0) = 0, y'(0) = 1 (residual and both conditions)"),
    P(CAT[8], "A Riccati equation with Airy solutions", o -> check_residual(o), "y' = x + y^2"),
    P(CAT[8], "A pendulum released from rest", o -> check_residual(o; extra = Dict(:a => 1.0)), "y'' + sin y = 0, y(0) = a, y'(0) = 0"),
    P(CAT[8], "Duffing's oscillator from rest", o -> check_residual(o; extra = Dict(:a => 1.0)), "y'' + y + y^3 = 0, y(0) = a, y'(0) = 0"),
    P(CAT[8], "A Jordan block", o -> check_vector(o, exp(0.7) .* [1 + 0.7 + 0.7^2 / 2, 1 + 0.7, 1]), "X' = J X, X(0) = (1,1,1), J the 3x3 Jordan block of 1; X(0.7)"),
    P(CAT[8], "The transport equation", o -> check_residual(o; var = :x, pts = (0.3, 0.7), extra = Dict(:y => 0.5)), "u_x + 2 u_y = 0, general solution: residual with the arbitrary function chosen"),
    P(CAT[8], "The heat equation", o -> check_residual(o; var = :x, pts = (0.3, 0.7, 2.0), extra = Dict(:t => 0.5)), "u_t = u_xx, u(0,t) = u(pi,t) = 0, u(x,0) = sin x: residual and the three conditions"),
    # ---- 9 Linear algebra ----
    P(CAT[9], "Symbolic eigenvalues", o -> check_vector(o, [1.3 - sqrt(2), 1.3, 1.3 + sqrt(2)]; sorted = true), "eigenvalues of [[a,1,0],[1,a,1],[0,1,a]], at a = 13/10"),
    P(CAT[9], "A Jordan form", o -> begin
          J = matrix_of(o)
          J === nothing && return :unverified
          size(J) == (4, 4) || return :wrong
          (sort(diag(J)) ≈ [1, 2, 4, 4] && count(!=(0), J - Diagonal(diag(J))) == 1) ? :verified : :wrong
      end, "the Jordan form J of a 4x4 with a block for the eigenvalue 4"),
    P(CAT[9], "A matrix exponential", o -> check_matrix(o, [cos(0.7) sin(0.7); -sin(0.7) cos(0.7)]), "exp(t [[0,1],[-1,0]]) at t = 7/10"),
    P(CAT[9], "A Vandermonde determinant", o -> check_factors(o, prod([1.3, 0.4, 0.7, -0.5, 3.0][j] - [1.3, 0.4, 0.7, -0.5, 3.0][i] for i in 1:5 for j in i+1:5), 10, Dict(:a => 1.3, :b => 0.4, :x => 0.7, :y => -0.5, :z => 3.0)),
      "factor det[v_i^(j-1)] for v = (a,b,x,y,z): 10 factors"),
    P(CAT[9], "A Smith normal form", o -> (D = matrix_of(o); D === nothing ? :unverified : (sort(abs.(diag(D))) ≈ [2, 6, 12] && count(!=(0), D - Diagonal(diag(D))) == 0 ? :verified : :wrong)), "Smith form of [[2,4,4],[-6,6,12],[10,-4,-16]]: diag(2,6,12)"),
    # ---- 10 Number theory ----
    P(CAT[10], "The Fermat number F7", o -> (o isa AbstractVector && length(o) == 2 && sort(big.(o)) == [big(59649589127497217), big"5704689200685129054721"]) ? :verified : (o isa AbstractVector ? :wrong : :unverified),
      "factor 2^128 + 1"),
    P(CAT[10], "A Mersenne prime", o -> check_bool(o, true), "2^521 - 1 is prime"),
    P(CAT[10], "A discrete logarithm", o -> (v = asbig(o); v === nothing ? :unverified : (powermod(big(5), v, big(1000000007)) == 123456789 ? :verified : :wrong)), "5^x = 123456789 mod 10^9+7"),
    P(CAT[10], "Pell's equation", o -> (o isa Tuple && length(o) == 2 ? ((xx, yy) = big.(o); xx > 1 && yy > 0 && xx^2 - 61yy^2 == 1 ? :verified : :wrong) : :unverified), "x^2 - 61 y^2 = 1 in positive integers"),
    P(CAT[10], "A periodic continued fraction", o -> (s = replace(string(o), r"[^0-9,;\[\]]" => ""); occursin(r"7[,;\[]+1,4,3,1,2,2,1,3,4,1,14", s) ? :verified : :unverified), "sqrt 61 = [7; 1,4,3,1,2,2,1,3,4,1,14 periodic]"),
    P(CAT[10], "Partitions", o -> check_integer(o, 3972999029388), "p(200) = 3972999029388"),
    # ---- 11 Transforms and special functions ----
    P(CAT[11], "A Laplace transform", o -> check_value(o, 0.052; at = Dict(:s => 2.0)), "L{t^2 e^-t sin t}(s), checked at s = 2: 13/250"),
    P(CAT[11], "An inverse Laplace transform", o -> check_value(o, (sin(0.7) - 0.7cos(0.7)) / 2; at = Dict(:t => 0.7)), "L^-1{1/(s^2+1)^2} = (sin t - t cos t)/2"),
    P(CAT[11], "A delayed step", o -> (v1 = tonum(EVAL(o, Dict(:t => 0.5))); v2 = tonum(EVAL(o, Dict(:t => 1.5))); (v1 === nothing || v2 === nothing) ? :unverified : (numeq(v1, 0.0; atol = 1e-9) && numeq(v2, 1.0) ? :verified : :wrong)),
      "L^-1{e^-s/s}(t) = theta(t-1), checked at t = 1/2 and 3/2"),
    P(CAT[11], "The series of Lambert's W", o -> check_value(o, 0.1 - 0.1^2 + 3 * 0.1^3 / 2 - 8 * 0.1^4 / 3 + 125 * 0.1^5 / 24; at = Dict(:x => 0.1)), "W(x) to order 5 at 0, polynomial part at x = 1/10"),
    P(CAT[11], "A hypergeometric function", o -> check_form(o, check_value(o, 2log(2); at = Dict(:x => 0.5)), !occursin("hyper", lowercase(string(o)))), "2F1(1,1;2;x) = -ln(1-x)/x"),
    P(CAT[11], "Gamma's reflection formula", o -> check_form(o, check_value(o, pi * sqrt(2)), !occursin("gamma", lowercase(string(o)))), "Gamma(1/4) Gamma(3/4) = pi sqrt 2"),
    P(CAT[11], "The sine integral's Laplace transform", o -> check_value(o, (pi / 2 - atan(2.0)) / 2; at = Dict(:s => 2.0)), "L{Si t}(s) = (pi/2 - atan s)/s, at s = 2"),
    P(CAT[11], "An inverse Laplace transform to a Bessel function", o -> check_value(o, J0_ref(0.7); at = Dict(:t => 0.7)), "L^-1{1/sqrt(s^2+1)} = J0(t), at t = 7/10"),
    P(CAT[11], "A polylogarithm value", o -> check_form(o, check_value(o, 0.5372131936080402009406), !occursin(r"polylog|li3|li\(", lowercase(string(o)))), "Li3(1/2) = 7/8 zeta(3) - pi^2/12 ln2 + ln^3 2/6"),
    # ---- 12 Control ----
    P(CAT[12], "A stability region", o -> check_intervals(o, [-0.5, 0.0, 7.0], [-1.5, 8.5, 10.0]), "for which k is s^3+3s^2+3s+1+k Hurwitz: -1 < k < 8"),
    P(CAT[12], "A Lyapunov equation", o -> check_matrix(o, [5/4 1/4; 1/4 1/4]), "A'P + PA = -I, A = [[0,1],[-2,-3]]"),
    P(CAT[12], "A Riccati equation (LQR)", o -> check_matrix(o, [sqrt(3) 1; 1 sqrt(3)]), "A'P + PA - PBB'P + I = 0, the positive definite solution"),
    P(CAT[12], "The unicycle's Lie algebra rank", o -> check_integer(o, 3), "rank{f1, f2, [f1,f2]}, f1 = (cos th, sin th, 0), f2 = (0,0,1)"),
    P(CAT[12], "A center manifold", o -> check_value(o, -0.01 - 2 * 0.0001; at = Dict(:x => 0.1)), "x' = xy, y' = -y - x^2: y = h(x) = -x^2 - 2x^4 + O(x^6), at x = 1/10"),
    P(CAT[12], "A sum-of-squares certificate", o -> check_bool(o, true), "x^4 - 2x^2 y + y^2 + x^2 - 2x + 1 >= 0 (a proof)"),
    P(CAT[12], "Motzkin's polynomial", o -> check_bool(o, true), "x^4 y^2 + x^2 y^4 - 3x^2 y^2 + 1 >= 0 (a proof; not a sum of squares)"),
    # ---- 13 Model to Jacobian (Brusselator on a ring of N cells, 2N states) ----
    P(CAT[13], "Jacobian: Brusselator N=10 (build)", o -> check_jacobian_build(o, 10), "the Jacobian of the 20-state model, compiled to a function"),
    P(CAT[13], "Jacobian: Brusselator N=50 (build)", o -> check_jacobian_build(o, 50), "the Jacobian of the 100-state model, compiled to a function"),
    P(CAT[13], "Jacobian: Brusselator N=10 (evaluate 1000 points)", o -> check_value(o, jacobian_trace_sum(10); rtol = 1e-6), "sum of traces of the compiled Jacobian over 1000 points"),
    P(CAT[13], "Jacobian: Brusselator N=50 (evaluate 1000 points)", o -> check_value(o, jacobian_trace_sum(50); rtol = 1e-6), "sum of traces of the compiled Jacobian over 1000 points"),
]

# the Brusselator ring: u_i' = 1 + u_i^2 v_i - 4 u_i + (u_{i+1} - 2 u_i + u_{i-1}),
# v_i' = 3 u_i - u_i^2 v_i + (v_{i+1} - 2 v_i + v_{i-1}); state order (u_1, v_1, ..., u_N, v_N)
function brusselator_jacobian_ref(N, u, v)
    J = zeros(2N, 2N)
    for i in 1:N
        ip, im = mod1(i + 1, N), mod1(i - 1, N)
        J[2i-1, 2i-1] = 2u[i] * v[i] - 4 - 2; J[2i-1, 2i] = u[i]^2
        J[2i-1, 2ip-1] += 1; J[2i-1, 2im-1] += 1
        J[2i, 2i-1] = 3 - 2u[i] * v[i]; J[2i, 2i] = -u[i]^2 - 2
        J[2i, 2ip] += 1; J[2i, 2im] += 1
    end
    J
end
point(N, k) = ([0.1i + 0.001k for i in 1:N], [0.2i + 0.002k for i in 1:N])
function jacobian_trace_sum(N)
    acc = 0.0
    for k in 1:1000
        u, v = point(N, k)
        acc += sum(diag(brusselator_jacobian_ref(N, u, v)))
    end
    acc
end
# a build task returns a Julia callable f(w::Vector) -> 2N x 2N matrix, w = (u1, v1, u2, v2, ...)
function check_jacobian_build(o, N)
    o isa Function || return :unverified
    u, v = point(N, 7)
    w = vec(permutedims(hcat(u, v)))
    M = try Float64.(o(w)) catch; return :unverified end
    size(M) == (2N, 2N) || return :wrong
    all(numeq.(M, brusselator_jacobian_ref(N, u, v); rtol = 1e-8, atol = 1e-10)) ? :verified : :wrong
end

# every solution of cos x = 1/2: the answer, with its integer parameter set to -1, 0 and 1
# through the adapter's EVALFAMILY, must give six distinct solutions in (-10, 10)
function check_periodic(out)
    s = replace(string(out), r"\b(Sym|Num|Any|Vector|GiacExpr|SymbolicUtils|BasicSymbolicImpl|SymReal|typeof|var)\b" => "", r"\{[^}]*\}" => "")
    occursin(r"pi|π", s) || return :unsolved          # a numeric family is not the exact answer asked
    params = unique(m.match for m in eachmatch(r"\b(?!pi\b)(?!x\b)[A-Za-z_][A-Za-z_0-9]*\b", s))
    isempty(params) && return :unsolved
    vals = Float64[]
    for kk in (-1, 0, 1)
        for v in EVALFAMILY(out, params, kk)
            v === nothing && return :unverified
            abs(cos(v) - 0.5) < 1e-8 || return :wrong
            -10 < v < 10 && push!(vals, v)
        end
    end
    length(unique(round.(vals; digits = 6))) >= 6 ? :verified : :unsolved
end

# the per-system tasks populate OPS (SYSTEM_KEY is set by lib/worker.jl)
include(joinpath(@__DIR__, "tasks_" * SYSTEM_KEY * ".jl"))
for (k, f) in TASKS
    OPS[Symbol(k)] = f
end
for p in PROBLEMS
    haskey(OPS, p.op) || (OPS[p.op] = missing)
end
isdefined(Main, :EVALFAMILY) || (EVALFAMILY(out, params, kk) = [nothing])
