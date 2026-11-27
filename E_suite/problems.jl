# Bench E: a problem suite written for this repository, in twelve categories from
# antiderivatives to number theory and a model-to-Jacobian pipeline. The problems
# are classical results whose reference values are computed or proved here; the
# statements are in E_suite/statements.tsv, the tasks of each system in
# E_suite/tasks_<system>.jl, written the way that system's user would write them.
#
# Every check is written here in plain Julia, system-neutral: a value to a
# tolerance (an exact answer when exactness is asked), an antiderivative by its
# derivative at points, solutions substituted and counted, differential equations
# by the residual with the constants given values, regions tested at points inside
# and outside, factorisations by their value and their number of factors.
# Identity differences are checked by explicit zero and high-precision evaluation.
#
# Statuses: verified (passes), unsolved (returned unevaluated, numeric where
# exact was asked, or not in the form asked), wrong (fails), unverified (the
# check could not evaluate the answer), unavailable (no such operation),
# error, timeout. A task returns the answer, or (answer, post) with post() an
# auxiliary computation (a residual) done outside the timed call.

using .BenchCommon: numeq
using LinearAlgebra: diag, Diagonal, I
include(joinpath(@__DIR__, "zero_reference.jl"))
isdefined(Main, :EVAL_HIGH_PRECISION) || (EVAL_HIGH_PRECISION(out, digits, at) = out isa Integer ? BigFloat(out) : nothing)

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
# A printed exact integer or rational can be evaluated without conversion
# through a system's machine-precision numeric API. Do not parse floats or
# arbitrary expressions as exact literals.
function exact_literal_value(out)
    m = match(r"^([+-]?\d+)(?:/{1,2}([1-9]\d*))?$", replace(string(out), " " => ""))
    m === nothing && return nothing
    n = parse(BigInt, m[1])
    d = m[2] === nothing ? big(1) : parse(BigInt, m[2])
    BigFloat(n) / BigFloat(d)
end

# High-precision checks for identity differences and non-zero controls.
# The independent real reference for each control is an MPFR enclosure.
function check_identity_high_precision(out, reference::Symbol; at = nothing)
    z = replace(string(out), " " => "") in ("0", "0.0", "0/1", "0//1")
    reference != :zero && z && return (:wrong, "numeric evaluation=0 (exact); certified reference is nonzero")
    value, source = setprecision(BigFloat, 256) do
        exact = exact_literal_value(out)
        exact === nothing ? (EVAL_HIGH_PRECISION(out, 80, at), "80-digit system evaluation") :
                            (exact, "256-bit evaluation of exact literal")
    end
    value === nothing && return (:unverified, "high-precision evaluation unavailable")
    isfinite(value) || return (:wrong, "high-precision evaluation is not finite")
    note = "numeric evaluation=$(string(value)); $source" * (at === nothing ? "" : "; x=$at")
    if reference == :zero
        # An unreduced identity can leave a small rounding residual even at
        # 80 digits. It remains unsolved rather than a false wrong result.
        abs(value) > big"1e-60" && return (:wrong, note)
        return z && iszero(value) ? (:verified_numeric, note) : (:unsolved, note * "; not reduced to zero")
    end
    reference in (:hardy, :rational) || error("unknown reference: $reference")
    lo, hi = reference == :hardy ? hardy_reference_interval() : rational_control_interval()
    lo <= value <= hi ? (:verified_numeric, note * "; inside 256-bit certified reference interval") :
                        (:wrong, note * "; outside 256-bit certified reference interval")
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

const CAT = ["Antiderivatives", "Definite integrals", "Series and products", "Limits", "Equations and inequalities",
             "Polynomials", "Simplification", "Differential equations", "Linear algebra", "Number theory",
             "Transforms and series expansions", "Model to Jacobian"]

# the answer of a partial fraction decomposition: the value of the rational function, written as a sum of at least
# three fractions (the input itself, one fraction, would pass a value check alone)
check_apart(o, ref, at) = (st = check_value(o, ref; at); st === :verified && count('/', string(o)) < 3 ? :unsolved : st)
# a resultant is defined up to sign by the order of its arguments
check_value_up_to_sign(o, ref; at) = (st = check_value(o, ref; at); st === :wrong && check_value(o, -ref; at) === :verified ? :verified : st)

const PROBLEMS = [
    # ---- 1 Antiderivatives ----
    P(CAT[1], "x^3 e^(2x)", o -> check_antiderivative(o, x -> x^3 * exp(2x)), "int x^3 e^(2x) dx"),
    P(CAT[1], "1/(x^3+1)", o -> check_antiderivative(o, x -> 1 / (x^3 + 1)), "int dx/(x^3+1)"),
    P(CAT[1], "sec^3 x", o -> check_antiderivative(o, x -> 1 / cos(x)^3), "int sec^3 x dx"),
    P(CAT[1], "x/(x^4+1)", o -> check_antiderivative(o, x -> x / (x^4 + 1)), "int x/(x^4+1) dx"),
    P(CAT[1], "ln(x)^2/x^2", o -> check_antiderivative(o, x -> log(x)^2 / x^2), "int ln(x)^2/x^2 dx"),
    P(CAT[1], "e^x sin x", o -> check_antiderivative(o, x -> exp(x) * sin(x)), "int e^x sin x dx"),
    P(CAT[1], "sqrt(1-x^2)", o -> check_antiderivative(o, x -> sqrt(1 - x^2); pts = (-0.5, 0.3, 0.7)), "int sqrt(1-x^2) dx"),
    P(CAT[1], "1/(x sqrt(x^2-1))", o -> check_antiderivative(o, x -> 1 / (x * sqrt(x^2 - 1)); pts = (1.3, 1.7, 2.4)), "int dx/(x sqrt(x^2-1)), x > 1"),
    P(CAT[1], "x asin x", o -> check_antiderivative(o, x -> x * asin(x); pts = (-0.5, 0.3, 0.7)), "int x asin x dx"),
    P(CAT[1], "1/(2+cos x)", o -> check_antiderivative(o, x -> 1 / (2 + cos(x))), "int dx/(2+cos x)"),
    # ---- 2 Definite integrals ----
    P(CAT[2], "Dalzell's integral", o -> check_exact_value(o, 22 / 7 - pi), "int_0^1 x^4(1-x)^4/(1+x^2) dx = 22/7 - pi"),
    P(CAT[2], "Dirichlet's integral", o -> check_exact_value(o, pi / 2), "int_0^inf sin x/x dx = pi/2"),
    P(CAT[2], "The Gaussian integral", o -> check_exact_value(o, sqrt(pi) / 2), "int_0^inf e^(-x^2) dx = sqrt(pi)/2"),
    P(CAT[2], "A logarithm over 1-x", o -> check_exact_value(o, -pi^2 / 6), "int_0^1 ln x/(1-x) dx = -pi^2/6"),
    P(CAT[2], "A power of the sine", o -> check_exact_value(o, 3pi / 8), "int_0^pi sin^4 x dx = 3 pi/8"),
    P(CAT[2], "Planck's integral", o -> check_exact_value(o, pi^4 / 15), "int_0^inf x^3/(e^x-1) dx = pi^4/15"),
    P(CAT[2], "x ln(1+x) on [0,1]", o -> check_exact_value(o, 0.25), "int_0^1 x ln(1+x) dx = 1/4"),
    P(CAT[2], "A quartic denominator on the line", o -> check_exact_value(o, pi / sqrt(2)), "int_-inf^inf dx/(x^4+1) = pi/sqrt 2"),
    P(CAT[2], "A damped sine", o -> check_exact_value(o, 0.5), "int_0^inf x e^(-x) sin x dx = 1/2"),
    # ---- 3 Series and products ----
    P(CAT[3], "zeta(6)", o -> check_exact_value(o, pi^6 / 945), "sum 1/n^6 = pi^6/945"),
    P(CAT[3], "n^3/3^n", o -> check_exact_value(o, 33 / 8), "sum_{n>=1} n^3/3^n = 33/8"),
    P(CAT[3], "The alternating harmonic series", o -> check_exact_value(o, log(2)), "sum_{n>=1} (-1)^(n+1)/n = ln 2"),
    P(CAT[3], "A telescoping sum", o -> check_exact_value(o, 0.25), "sum_{n>=1} 1/(n(n+1)(n+2)) = 1/4"),
    P(CAT[3], "Leibniz's series", o -> check_exact_value(o, pi / 4), "sum_{n>=0} (-1)^n/(2n+1) = pi/4"),
    P(CAT[3], "The binomial theorem at 2", o -> check_exact_value(o, 6561.0; at = Dict(:n => 8.0)), "sum_{k=0}^n binomial(n,k) 2^k = 3^n, checked at n = 8"),
    P(CAT[3], "Nicomachus's theorem", o -> check_exact_value(o, 6084.0; at = Dict(:n => 12.0)), "sum_{k=1}^n k^3 = (n(n+1)/2)^2, checked at n = 12"),
    P(CAT[3], "1/(4n^2-1)", o -> check_exact_value(o, 0.5), "sum_{n>=1} 1/(4n^2-1) = 1/2"),
    P(CAT[3], "A product equal to 2", o -> check_exact_value(o, 2.0), "prod_{n>=1} (n+1)^2/(n(n+2)) = 2"),
    # ---- 4 Limits ----
    P(CAT[4], "(e^x-1-x)/x^2", o -> check_exact_value(o, 0.5), "lim_{x->0} (e^x-1-x)/x^2 = 1/2"),
    P(CAT[4], "(1-cos x)/x^2", o -> check_exact_value(o, 0.5), "lim_{x->0} (1-cos x)/x^2 = 1/2"),
    P(CAT[4], "(1+2/x)^x", o -> check_exact_value(o, exp(2.0)), "lim_{x->inf} (1+2/x)^x = e^2"),
    P(CAT[4], "x^x at 0", o -> check_exact_value(o, 1.0), "lim_{x->0+} x^x = 1"),
    P(CAT[4], "(sin x - x)/x^3", o -> check_exact_value(o, -1 / 6), "lim_{x->0} (sin x - x)/x^3 = -1/6"),
    P(CAT[4], "n(2^(1/n)-1)", o -> check_exact_value(o, log(2)), "lim_{n->inf} n(2^(1/n)-1) = ln 2"),
    P(CAT[4], "sqrt(x^2+x)-x", o -> check_exact_value(o, 0.5), "lim_{x->inf} sqrt(x^2+x)-x = 1/2"),
    P(CAT[4], "(tan x - x)/x^3", o -> check_exact_value(o, 1 / 3), "lim_{x->0} (tan x - x)/x^3 = 1/3"),
    P(CAT[4], "1/x - 1/(e^x-1)", o -> check_exact_value(o, 0.5), "lim_{x->0} 1/x - 1/(e^x-1) = 1/2"),
    # ---- 5 Equations and inequalities ----
    P(CAT[5], "A cubic with integer roots", o -> check_solutions(o, x -> (x^3 - 6x^2 + 11x - 6,), 3), "x^3-6x^2+11x-6 = 0: three roots"),
    P(CAT[5], "Sum and product", o -> check_solutions(o, (x, y) -> (x + y - 5, x * y - 6), 2), "x+y = 5, xy = 6: two solutions"),
    P(CAT[5], "A biquadratic", o -> check_solutions(o, x -> (x^4 - 10x^2 + 1,), 4), "x^4-10x^2+1 = 0: four roots"),
    P(CAT[5], "An exponential equation", o -> check_solutions(o, x -> (2^x - 3^(x - 1),), 1), "2^x = 3^(x-1): one real solution"),
    P(CAT[5], "A circle and a line", o -> check_solutions(o, (x, y) -> (x^2 + y^2 - 25, x - y - 1), 2), "x^2+y^2 = 25, x-y = 1: two solutions"),
    P(CAT[5], "A cubic with one real root", o -> check_solutions(o, x -> (x^3 + x - 1,), 3), "x^3+x-1 = 0: all three complex roots"),
    P(CAT[5], "A quadratic inequality", o -> check_intervals(o, [1.1, 1.5, 1.9], [0.5, 0.9, 2.1, 3.0]), "x^2-3x+2 < 0"),
    P(CAT[5], "An absolute value inequality", o -> check_intervals(o, [-0.9, 0.0, 3.9], [-1.5, -1.1, 4.1, 5.0]), "|2x-3| < 5"),
    # ---- 6 Polynomials ----
    P(CAT[6], "x^8-1 over Q", o -> check_factors(o, 0.7^8 - 1, 4, Dict(:x => 0.7)), "factor x^8-1 over Q: 4 factors"),
    P(CAT[6], "Sophie Germain's identity", o -> check_factors(o, 0.7^4 + 4, 2, Dict(:x => 0.7)), "factor x^4+4: 2 factors"),
    P(CAT[6], "x^3+y^3+z^3-3xyz", o -> check_factors(o, 0.7^3 + 0.4^3 + 0.3^3 - 3 * 0.7 * 0.4 * 0.3, 2, Dict(:x => 0.7, :y => 0.4, :z => 0.3)),
      "factor x^3+y^3+z^3-3xyz: 2 factors"),
    P(CAT[6], "A polynomial gcd", o -> check_value(o, 0.7^2 - 1; at = Dict(:x => 0.7)), "gcd(x^4-1, x^6-1) = x^2-1, checked at x = 0.7"),
    P(CAT[6], "A resultant", o -> check_value_up_to_sign(o, 2 * 0.7^2 - 1; at = Dict(:x => 0.7)), "res_y(x^2+y^2-1, x-y) = 2x^2-1, checked at x = 0.7"),
    P(CAT[6], "A discriminant", o -> check_value(o, -275.0; at = Dict(:p => 2.0, :q => 3.0)), "disc_x(x^3+px+q) = -4p^3-27q^2, checked at p = 2, q = 3"),
    P(CAT[6], "A partial fraction decomposition", o -> check_apart(o, 1 / ((0.7 - 1) * (0.7 + 2)^2), Dict(:x => 0.7)), "1/((x-1)(x+2)^2) in partial fractions"),
    P(CAT[6], "Two conics", o -> check_solutions(o, (x, y) -> (x^2 + y^2 - 1, x * y - 0.25), 4), "x^2+y^2 = 1, xy = 1/4: four solutions"),
    # ---- 7 Simplification ----
    P(CAT[7], "A nested radical", o -> check_identity_high_precision(o, :zero), "simplify sqrt(7+4 sqrt 3) - 2 - sqrt 3"),
    P(CAT[7], "The Pythagorean identity", o -> check_identity_high_precision(o, :zero; at = 7//10), "simplify sin(x)^2 + cos(x)^2 - 1"),
    P(CAT[7], "A removable singularity", o -> check_identity_high_precision(o, :zero; at = 7//10), "simplify (x^3-1)/(x-1) - x^2 - x - 1"),
    P(CAT[7], "The golden cosine", o -> check_identity_high_precision(o, :zero), "simplify cos(pi/5) - (1+sqrt 5)/4"),
    P(CAT[7], "tan(pi/12)", o -> check_identity_high_precision(o, :zero), "simplify tan(pi/12) - 2 + sqrt 3"),
    P(CAT[7], "A minimal polynomial of degree six", o -> check_value(o, 0.7^6 - 6 * 0.7^4 - 6 * 0.7^3 + 12 * 0.7^2 - 36 * 0.7 + 1; at = Dict(:x => 0.7)),
      "minimal polynomial of sqrt 2 + cbrt 3, checked at x = 0.7"),
    P(CAT[7], "An exponential of a logarithm", o -> check_identity_high_precision(o, :zero; at = 7//10), "simplify exp(2 ln x) - x^2, for x > 0"),
    P(CAT[7], "Zero identity: nested square root", o -> check_identity_high_precision(o, :zero), "sqrt(3+2 sqrt(2)) - 1 - sqrt(2)"),
    P(CAT[7], "Zero identity: nested cube root", o -> check_identity_high_precision(o, :zero), "cbrt(7+5 sqrt(2)) - 1 - sqrt(2)"),
    P(CAT[7], "Zero identity: logarithms on positive reals", o -> check_identity_high_precision(o, :zero), "log(2) + log(3) - log(6)"),
    P(CAT[7], "Zero identity: exponential of a logarithm", o -> check_identity_high_precision(o, :zero), "exp(log(2)) - 2 on the positive reals"),
    P(CAT[7], "Zero identity: sine at pi over six", o -> check_identity_high_precision(o, :zero), "sin(pi/6) - 1/2"),
    P(CAT[7], "Nonzero control: rational residual", o -> check_identity_high_precision(o, :rational), "sqrt(2)^2 - 2 + 10^(-30): exact reference 1/10^30"),
    P(CAT[7], "Nonzero control: near integer", o -> check_identity_high_precision(o, :hardy), "exp(pi sqrt(163)) - 262537412640768744: certified negative interval"),
    # ---- 8 Differential equations ----
    P(CAT[8], "A harmonic oscillator", o -> check_residual(o), "y'' + 4y = 0"),
    P(CAT[8], "A forced linear equation", o -> check_residual(o), "y'' - 3y' + 2y = e^(3x)"),
    P(CAT[8], "A first-order linear equation", o -> check_residual(o), "y' + 2xy = x"),
    P(CAT[8], "A first-order Euler equation", o -> check_residual(o), "x y' - y = x^2"),
    P(CAT[8], "A polynomial forcing", o -> check_residual(o), "y'' + y = x"),
    P(CAT[8], "A separable equation", o -> check_residual(o), "y' = y^2"),
    P(CAT[8], "An initial-value problem", o -> check_residual(o), "y'' + y' - 2y = 0, y(0) = 1, y'(0) = 0 (residual and both conditions)"),
    P(CAT[8], "A repeated characteristic root", o -> check_residual(o), "y'' - 2y' + y = 0"),
    # ---- 9 Linear algebra ----
    P(CAT[9], "A tridiagonal determinant", o -> check_value(o, 4.0), "det [[2,1,0],[1,2,1],[0,1,2]] = 4"),
    P(CAT[9], "A 2x2 inverse", o -> check_matrix(o, [0.6 -0.7; -0.2 0.4]), "inverse of [[4,7],[2,6]]"),
    P(CAT[9], "Eigenvalues of a symmetric matrix", o -> check_vector(o, [1.0, 3.0]; sorted = true), "eigenvalues of [[2,1],[1,2]]"),
    P(CAT[9], "The rank of a singular matrix", o -> check_integer(o, 2), "rank of [[1,2,3],[4,5,6],[7,8,9]] = 2"),
    P(CAT[9], "A linear system", o -> check_vector(o, [2.0, 3.0, -1.0]), "[[2,1,-1],[-3,-1,2],[-2,1,2]] X = (8,-11,-3)"),
    P(CAT[9], "A characteristic polynomial", o -> check_value(o, 0.7^2 - 5 * 0.7 - 2; at = Dict(:x => 0.7)), "characteristic polynomial of [[1,2],[3,4]] in x, checked at x = 0.7"),
    P(CAT[9], "A Fibonacci matrix power", o -> check_matrix(o, [89.0 55.0; 55.0 34.0]), "[[1,1],[1,0]]^10"),
    P(CAT[9], "A symbolic determinant", o -> check_value(o, 1.3^2 - 0.4^2; at = Dict(:a => 1.3, :b => 0.4)), "det [[a,b],[b,a]] = a^2-b^2, checked at a = 1.3, b = 0.4"),
    # ---- 10 Number theory ----
    P(CAT[10], "The Fermat number F6", o -> (o isa AbstractVector && length(o) == 2 && sort(big.(o)) == [big(274177), big(67280421310721)]) ? :verified : (o isa AbstractVector ? :wrong : :unverified),
      "factor 2^64 + 1"),
    P(CAT[10], "A Mersenne prime of 89 bits", o -> check_bool(o, true), "2^89 - 1 is prime"),
    P(CAT[10], "A gcd of Mersenne numbers", o -> check_integer(o, 4095), "gcd(2^60-1, 2^84-1) = 2^12-1"),
    P(CAT[10], "A modular inverse", o -> check_integer(o, 2753), "17^-1 mod 3120 = 2753"),
    P(CAT[10], "Euler's totient of a million", o -> check_integer(o, 400000), "phi(10^6) = 400000"),
    P(CAT[10], "The next prime after 10^12", o -> check_integer(o, 1000000000039), "the least prime > 10^12"),
    P(CAT[10], "The Chinese remainder theorem", o -> check_integer(o, 23), "x = 2 mod 3, x = 3 mod 5, x = 2 mod 7: x = 23 mod 105"),
    P(CAT[10], "A sum of divisors", o -> check_integer(o, 1170), "sigma(360) = 1170"),
    # ---- 11 Transforms and series expansions ----
    P(CAT[11], "A Laplace transform", o -> check_value(o, 1 / 9; at = Dict(:s => 1.0)), "L{t e^(-2t)}(s) = 1/(s+2)^2, checked at s = 1"),
    P(CAT[11], "An inverse Laplace transform", o -> check_value(o, sin(1.4) / 2; at = Dict(:t => 0.7)), "L^-1{1/(s^2+4)}(t) = sin(2t)/2, checked at t = 0.7"),
    P(CAT[11], "The Laplace transform of a cosine", o -> check_value(o, 0.2; at = Dict(:s => 1.0)), "L{cos 2t}(s) = s/(s^2+4), checked at s = 1"),
    P(CAT[11], "Gamma at one half", o -> check_exact_value(o, sqrt(pi)), "Gamma(1/2) = sqrt(pi)"),
    P(CAT[11], "A Beta value", o -> check_exact_value(o, 1 / 12), "B(2,3) = 1/12"),
    P(CAT[11], "Gamma at five halves", o -> check_exact_value(o, 3 * sqrt(pi) / 4), "Gamma(5/2) = 3 sqrt(pi)/4"),
    P(CAT[11], "The series of tan", o -> check_value(o, 0.1 + 0.1^3 / 3 + 2 * 0.1^5 / 15 + 17 * 0.1^7 / 315; at = Dict(:x => 0.1)),
      "tan x to order 7 at 0, polynomial part at x = 1/10"),
    P(CAT[11], "The series of e^x sin x", o -> check_value(o, 0.1 + 0.1^2 + 0.1^3 / 3 - 0.1^5 / 30; at = Dict(:x => 0.1)),
      "e^x sin x to order 5 at 0, polynomial part at x = 1/10"),
    # ---- 12 Model to Jacobian (Brusselator on a ring of N cells, 2N states) ----
    P(CAT[12], "Jacobian: Brusselator N=10 (build)", o -> check_jacobian_build(o, 10), "the Jacobian of the 20-state model, compiled to a function"),
    P(CAT[12], "Jacobian: Brusselator N=50 (build)", o -> check_jacobian_build(o, 50), "the Jacobian of the 100-state model, compiled to a function"),
    P(CAT[12], "Jacobian: Brusselator N=10 (evaluate 1000 points)", o -> check_value(o, jacobian_trace_sum(10); rtol = 1e-6), "sum of traces of the compiled Jacobian over 1000 points"),
    P(CAT[12], "Jacobian: Brusselator N=50 (evaluate 1000 points)", o -> check_value(o, jacobian_trace_sum(50); rtol = 1e-6), "sum of traces of the compiled Jacobian over 1000 points"),
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

# the per-system tasks populate OPS (SYSTEM_KEY is set by lib/worker.jl)
include(joinpath(@__DIR__, "tasks_" * SYSTEM_KEY * ".jl"))
for (k, f) in TASKS
    OPS[Symbol(k)] = f
end
for p in PROBLEMS
    haskey(OPS, p.op) || (OPS[p.op] = missing)
end
isdefined(Main, :EVALFAMILY) || (EVALFAMILY(out, params, kk) = [nothing])
