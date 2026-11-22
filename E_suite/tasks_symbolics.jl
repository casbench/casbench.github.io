# Bench E tasks for Symbolics.jl 7.49 (with Nemo, Groebner, RischIntegrate,
# SpecialFunctions and Primes). Only operations the package documents are
# wired; the others are `missing` (unavailable). A task that raises is an
# error; its message is kept in the results so that an adapter mistake can
# be told from a package limitation.
using SpecialFunctions
using LinearAlgebra: det, rank
const RI = RischIntegrate
C6 = [Symbolics.variable(Symbol("c$i")) for i in 1:6]
for i in 1:6
    VAR[Symbol("c$i")] = C6[i]
end
@variables th p q r px py 𝑦
VAR[:th] = th; VAR[:px] = px; VAR[:py] = py
fl(e) = (v = Symbolics.value(e); v isa Number ? Float64(real(v)) : Float64(real(SymbolicUtils.unwrap_const(v))))
# a numeric (possibly complex) value of a constant expression, folded
function cnum(e)
    v = SymbolicUtils.substitute(unwrap(e), Dict{Any,Any}(); fold = Val(true))
    v isa SymbolicUtils.BasicSymbolic && (v = SymbolicUtils.unwrap_const(v))
    v isa Number ? ComplexF64(v) : error("not a number: $e")
end
risch(f) = RI.integrate(unwrap(f), unwrap(x))
# a definite integral: the antiderivative, evaluated at the bounds (RischIntegrate's definite
# form calls the antiderivative, which SymbolicUtils terms do not support); an infinite bound
# goes through Symbolics.limit
function def(f, lo, hi)
    F = Num(RI.integrate(unwrap(f), unwrap(x)))
    function at(b)
        if isfinite(b)
            v = Symbolics.substitute(F, Dict(x => b))
            vv = tonum(EVAL(v, Dict{Symbol,Float64}()))
            (vv !== nothing && isfinite(vv)) && return v        # a finite value by substitution
        end
        Num(Symbolics.limit(unwrap(F), unwrap(x), b))           # otherwise a limit at the bound
    end
    at(hi) - at(lo)
end
cyclic6() = begin
    polys = Num[]
    for m in 1:5
        push!(polys, sum(prod(C6[mod1(kk + j, 6)] for j in 0:m-1) for kk in 1:6))
    end
    push!(polys, prod(C6) - 1)
    polys
end
Dx = Differential(x)
# a linear ODE y'' + p1 y' + p0 y = rhs through SymbolicLinearODE, with the residual at constants = 1
function linode(residual, p_coeffs, rhs)
    ode = SymbolicLinearODE(𝑦, x, p_coeffs, rhs)      # 𝑦 is the unknown as a plain variable, as in the docstring
    sol = symbolic_solve_ode(ode)
    sol === nothing && return nothing
    post = () -> begin
        y1 = Symbolics.substitute(sol, Dict(cc => 1 for cc in ode.C))
        [Symbolics.simplify(expand_derivatives(residual(y1)))]
    end
    (sol, post)
end
function bruss(N)
    U = [Symbolics.variable(Symbol("u$i")) for i in 1:N]; V = [Symbolics.variable(Symbol("v$i")) for i in 1:N]
    eqs = Num[]; vars = Num[]
    for i in 1:N
        ip, im = mod1(i + 1, N), mod1(i - 1, N)
        push!(eqs, 1 + U[i]^2 * V[i] - 4U[i] + (U[ip] - 2U[i] + U[im])); push!(eqs, 3U[i] - U[i]^2 * V[i] + (V[ip] - 2V[i] + V[im]))
        push!(vars, U[i]); push!(vars, V[i])
    end
    eqs, vars
end
function jacobian_fn(N)
    eqs, vars = bruss(N)
    J = Symbolics.jacobian(eqs, vars)
    f = Symbolics.build_function(J, vars; expression = Val(false))[1]
    w -> f(w)
end
function jacobian_eval(N)
    f = jacobian_fn(N)
    acc = 0.0
    for k in 1:1000
        w = vec(permutedims(hcat([0.1i + 0.001k for i in 1:N], [0.2i + 0.002k for i in 1:N])))
        M = f(w)
        for i in 1:2N
            acc += M[i, i]
        end
    end
    acc
end

const TASKS = Dict{String,Any}(
    "sqrt(tan x)" => () -> risch(sqrt(tan(x))),
    "Chebyshev's pseudo-elliptic integral" => () -> risch(x / sqrt(x^4 + 10x^2 - 96x - 71)),
    "An arctangent of a radical" => () -> risch((x^2 - 1) / ((x^2 + 1) * sqrt(x^4 + 1))),
    "A quintic denominator" => () -> risch(1 / (x^5 - x + 1)),
    "A fourth root" => () -> risch(1 / (1 + x^4)^(1 // 4)),
    "Parts, twice" => () -> risch(x^2 * asin(x)^2),
    "Exponential and logarithm (Risch)" => () -> risch(exp(x) * (1 + x * log(x)) / x),
    "A Bessel function, to Struve functions" => () -> risch(x^2 * SpecialFunctions.besselj0(x)),
    "The error function squared" => () -> risch(SpecialFunctions.erf(x)^2),
    "Bose-Einstein type" => () -> def(x / (exp(x) - 1), 0, Inf),
    "Serret's integral" => () -> def(log(1 + x) / (1 + x^2), 0, 1),
    "A symmetry trick" => () -> def(x * sin(x) / (1 + cos(x)^2), 0, pi),
    "Log-sine" => () -> def(log(sin(x)), 0, pi / 2),
    "Ahmed's integral" => () -> def(atan(sqrt(x^2 + 2)) / ((x^2 + 1) * sqrt(x^2 + 2)), 0, 1),
    "Laplace's integral" => () -> def(cos(x) / (1 + x^2), 0, Inf),
    "A dilogarithm value" => () -> def(log(x) * log(1 - x), 0, 1),
    "Euler's constant" => () -> def(exp(-x) * log(x)^2, 0, Inf),
    "A Gaussian with a cosine" => () -> def(exp(-x^2) * cos(2x), -Inf, Inf),
    "Frullani's integral" => () -> def((exp(-x) - exp(-2x)) / x, 0, Inf),
    "The error function" => () -> def(SpecialFunctions.erfc(x)^2, 0, Inf),
    "A Bessel function on the half-line" => () -> def(SpecialFunctions.besselj0(x), 0, Inf),
    "A damped Bessel function" => () -> def(exp(-x) * SpecialFunctions.besselj0(x), 0, Inf),
    "A pendulum's period" => missing,
    "zeta(4)" => missing, "Harmonic numbers" => missing, "Dirichlet beta(3)" => missing, "Arithmetic-geometric" => missing,
    "A central binomial series" => missing, "Vandermonde's identity" => missing, "A closed form in n" => missing,
    "A polylogarithm value" => missing, "A telescoping product" => missing, "Wallis's product" => missing,
    "tan sin - sin tan" => () -> Symbolics.limit(unwrap((tan(sin(x)) - sin(tan(x))) / x^7), unwrap(x), 0),
    "Stirling" => missing,
    "A second-order term of e" => () -> Symbolics.limit(unwrap(x * ((1 + 1 / x)^x - exp(1))), unwrap(x), Inf),
    "Nested exponentials (Gruntz)" => () -> Symbolics.limit(unwrap(exp(x) * (exp(1 / x - exp(-x)) - exp(1 / x))), unwrap(x), Inf),
    "Cancelling poles" => () -> Symbolics.limit(unwrap(1 / x^2 - 1 / sin(x)^2), unwrap(x), 0),
    "A ratio of Gamma functions" => missing,
    "A power of sinc" => () -> Symbolics.limit(unwrap((sin(x) / x)^(1 / x^2)), unwrap(x), 0),
    "A bounded oscillation" => () -> Symbolics.limit(unwrap((x + sin(x)) / x), unwrap(x), Inf),
    "A sextic system" => () -> (sols = symbolic_solve([x^2 + y^2 - 1, x^3 - y], [x, y]); try [(cnum(d[x]), cnum(d[y])) for d in sols] catch; sols end),
    "A quintic solvable by radicals" => () -> symbolic_solve(x^5 - 5x + 12, x),
    "Every solution of cos x = 1/2" => () -> symbolic_solve(cos(x) ~ 1 // 2, x),
    "Lambert's W" => missing,
    "A symmetric system" => () -> (sols = symbolic_solve([x + y + z - 6, x * y + y * z + z * x - 11, x * y * z - 6], [x, y, z]); try [(cnum(d[x]), cnum(d[y]), cnum(d[z])) for d in sols] catch; sols end),
    "A quartic inequality" => missing, "Absolute values" => missing, "Quantifier elimination" => missing,
    "Cyclotomic factors" => () -> FACTOR(x^105 - 1),
    "A symmetric septic" => () -> FACTOR((x + y + z)^7 - x^7 - y^7 - z^7),
    "Factoring over Q(sqrt 2)" => missing,
    "The cyclic-6 system" => missing,          # a Groebner basis, but no solution count
    "Implicitization" => missing, "Polynomial decomposition" => missing,
    "Denesting" => () -> (log_input!("Symbolics.simplify(sqrt(5+2*sqrt(Num(6)))-sqrt(Num(2))-sqrt(Num(3)))"); Symbolics.simplify(sqrt(5 + 2sqrt(Num(6))) - sqrt(Num(2)) - sqrt(Num(3)))),
    "Ramanujan's denesting" => missing,
    "A heptagon sum" => () -> (log_input!("Symbolics.simplify(cos(2*VAR[:pi]/7)+cos(4*VAR[:pi]/7)+cos(6*VAR[:pi]/7)+Num(1)/2)"); Symbolics.simplify(cos(2VAR[:pi] / 7) + cos(4VAR[:pi] / 7) + cos(6VAR[:pi] / 7) + Num(1)/2)),
    "A minimal polynomial" => missing,
    "A trigonometric identity" => () -> (log_input!("simplify(sin(3*x)/sin(x)-cos(3*x)/cos(x)-2)"); Symbolics.simplify(sin(3x) / sin(x) - cos(3x) / cos(x) - 2)),
    "Gauss's 17-gon" => missing, "An inverse cosine, with assumptions" => missing,
    "Airy" => () -> linode(y1 -> Dx(Dx(y1)) - x * y1, [-x, 0], 0),
    "Bessel, order 1/2" => () -> linode(y1 -> x^2 * Dx(Dx(y1)) + x * Dx(y1) + (x^2 - 1 // 4) * y1, [(x^2 - 1 // 4) / x^2, 1 / x], 0),
    "Riccati" => missing, "A nonlinear autonomous equation" => missing, "Bernoulli" => missing,
    "A forced Euler-Cauchy equation" => () -> linode(y1 -> x^2 * Dx(Dx(y1)) - 3x * Dx(y1) + 4y1 - x^2 * log(x), [4 / x^2, -3 / x], log(x)),
    "An exponential solution (Kovacic)" => () -> linode(y1 -> Dx(Dx(y1)) - (x^2 + 1) * y1, [-(x^2 + 1), 0], 0),
    "A forced initial-value problem" => () -> begin
        SymbolicUtils.@syms 𝑓(x)::Real
        sol = Symbolics.laplace_solve_ode(Dx(Dx(𝑓(x))) - (x^2 + 1) * 𝑓(x) ~ x * exp(-x^2 / 2), 𝑓, x, [0, 1])
        sol === nothing && return nothing
        post = () -> [Symbolics.simplify(expand_derivatives(Dx(Dx(sol)) - (x^2 + 1) * sol - x * exp(-x^2 / 2))),
                      Symbolics.substitute(sol, Dict(x => 0)), Symbolics.substitute(expand_derivatives(Dx(sol)), Dict(x => 0)) - 1]
        (sol, post)
    end,
    "A Riccati equation with Airy solutions" => missing, "A pendulum released from rest" => missing, "Duffing's oscillator from rest" => missing,
    "A Jordan block" => () -> [tonum(EVAL(e, Dict(:t => 0.7))) for e in solve_linear_ode_system([1 1 0; 0 1 1; 0 0 1], [1, 1, 1], t)],
    "The transport equation" => missing, "The heat equation" => missing,
    "Symbolic eigenvalues" => missing, "A Jordan form" => missing, "A matrix exponential" => missing,
    "A Vandermonde determinant" => () -> FACTOR(det(Num[v^j for v in (a, b, x, y, z), j in 0:4])),
    "A Smith normal form" => missing,
    "The Fermat number F7" => () -> sort([big(pp) for (pp, e) in Primes.factor(big(2)^128 + 1)]),
    "A Mersenne prime" => () -> Primes.isprime(big(2)^521 - 1),
    "A discrete logarithm" => missing, "Pell's equation" => missing, "A periodic continued fraction" => missing, "Partitions" => missing,
    "A Laplace transform" => () -> LAPLACE(t^2 * exp(-t) * sin(t), t, s),
    "An inverse Laplace transform" => () -> ILAPLACE(1 / (s^2 + 1)^2, s, t),
    "A delayed step" => () -> ILAPLACE(exp(-s) / s, s, t),
    "The series of Lambert's W" => missing, "A hypergeometric function" => missing,
    "Gamma's reflection formula" => () -> Symbolics.simplify(SpecialFunctions.gamma(Num(1 // 4)) * SpecialFunctions.gamma(Num(3 // 4))),
    "The sine integral's Laplace transform" => missing, "An inverse Laplace transform to a Bessel function" => missing, "A polylogarithm value" => missing,
    "A stability region" => missing,
    "A Lyapunov equation" => () -> (sol = symbolic_linear_solve([-4q + 1 ~ 0, p - 3q - 2r ~ 0, 2q - 6r + 1 ~ 0], [p, q, r]); [fl(sol[1]) fl(sol[2]); fl(sol[2]) fl(sol[3])]),
    "A Riccati equation (LQR)" => () -> begin
        for d in symbolic_solve([-q^2 + 1, p - q * r, 2q - r^2 + 1], [p, q, r])
            vals = (Symbolics.value(d[p]), Symbolics.value(d[q]), Symbolics.value(d[r]))
            all(v -> v isa Real, vals) || continue
            pp, qq, rr = Float64.(vals)
            pp > 0 && pp * rr - qq^2 > 0 && return [pp qq; qq rr]
        end
        nothing
    end,
    "The unicycle's Lie algebra rank" => () -> begin
        # the bracket symbolically; the rank of the symbolic matrix is taken at th = 0.3
        f1 = [cos(th), sin(th), 0]; f2 = [0, 0, 1]; X = [px, py, th]
        br = Symbolics.jacobian(f2, X) * f1 - Symbolics.jacobian(f1, X) * f2
        M = [tonum(EVAL(e, Dict(:th => 0.3))) for e in hcat(f1, f2, br)]
        rank(Float64.(M))
    end,
    "A center manifold" => () -> begin
        @variables c2 c3 c4
        h = c2 * x^2 + c3 * x^3 + c4 * x^4
        rr = Symbolics.expand(expand_derivatives(Dx(h)) * x * h + h + x^2)
        d = symbolic_solve([Symbolics.coeff(rr, x^2), Symbolics.coeff(rr, x^3), Symbolics.coeff(rr, x^4)], [c2, c3, c4])[1]
        Symbolics.substitute(h, d)
    end,
    "A sum-of-squares certificate" => missing, "Motzkin's polynomial" => missing,
    "Jacobian: Brusselator N=10 (build)" => () -> jacobian_fn(10),
    "Jacobian: Brusselator N=50 (build)" => () -> jacobian_fn(50),
    "Jacobian: Brusselator N=10 (evaluate 1000 points)" => () -> jacobian_eval(10),
    "Jacobian: Brusselator N=50 (evaluate 1000 points)" => () -> jacobian_eval(50),
)

# the family of solutions of cos x = 1/2: every free symbol other than x set to kk
function EVALFAMILY(out, params, kk)
    vals = Any[]
    for e in (out isa AbstractVector ? out : [out])
        syms = [v for v in Symbolics.get_variables(Num(e)) if !isequal(v, unwrap(x))]
        d = Dict{Any,Any}(v => kk for v in syms)
        r = SymbolicUtils.substitute(unwrap(e), d; fold = Val(true))
        r isa SymbolicUtils.BasicSymbolic && (r = SymbolicUtils.unwrap_const(r))
        push!(vals, r isa Real ? Float64(r) : nothing)
    end
    vals
end

const ZERO_CASE_INPUTS = Dict(
    "Zero identity: nested square root" => "sqrt(3 + 2sqrt(Num(2))) - 1 - sqrt(Num(2))",
    "Zero identity: nested cube root" => "(7 + 5sqrt(Num(2)))^(Num(1)/3) - 1 - sqrt(Num(2))",
    "Zero identity: logarithms on positive reals" => "log(Num(2)) + log(Num(3)) - log(Num(6))",
    "Zero identity: exponential of a logarithm" => "exp(log(Num(2))) - 2",
    "Zero identity: sine at pi over six" => "sin(VAR[:pi]/6) - Num(1)/2",
    "Nonzero control: rational residual" => "sqrt(Num(2))^2 - 2 + Num(1)/Num(big(10)^30)",
    "Nonzero control: near integer" => "exp(VAR[:pi]*sqrt(Num(163))) - Num(262537412640768744)",
)

for (name, build) in (
    "Zero identity: nested square root" => (() -> sqrt(3 + 2sqrt(Num(2))) - 1 - sqrt(Num(2))),
    "Zero identity: nested cube root" => (() -> (7 + 5sqrt(Num(2)))^(Num(1)/3) - 1 - sqrt(Num(2))),
    "Zero identity: logarithms on positive reals" => (() -> log(Num(2)) + log(Num(3)) - log(Num(6))),
    "Zero identity: exponential of a logarithm" => (() -> exp(log(Num(2))) - 2),
    "Zero identity: sine at pi over six" => (() -> sin(VAR[:pi]/6) - Num(1)/2),
    "Nonzero control: rational residual" => (() -> sqrt(Num(2))^2 - 2 + Num(1)/Num(big(10)^30)),
    "Nonzero control: near integer" => (() -> exp(VAR[:pi]*sqrt(Num(163))) - Num(262537412640768744)),
)
    TASKS[name] = () -> begin
        log_input!(ZERO_CASE_INPUTS[name])
        ex = build()
        log_input!("simplify(" * string(ex) * ")")
        Symbolics.simplify(ex)
    end
end
