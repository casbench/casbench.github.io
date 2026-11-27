# Bench E tasks for Symbolics.jl (with RischIntegrate.jl for integrals, Nemo for
# polynomial factorisation, Primes.jl for the integer factorisation Symbolics
# forwards to), written for this repository. Only operations the packages
# document are wired; the others are `missing` (unavailable). A task returns the
# answer, or (answer, post) with post() a residual computed outside the timed call.
using SpecialFunctions
using LinearAlgebra: I
const RI = RischIntegrate
fl(e) = (v = Symbolics.value(e); v isa Number ? Float64(real(v)) : Float64(real(SymbolicUtils.unwrap_const(v))))
# a numeric (possibly complex) value of a constant expression, folded
function cnum(e)
    v = SymbolicUtils.substitute(unwrap(Num(e)), Dict{Any,Any}(); fold = Val(true))
    v isa SymbolicUtils.BasicSymbolic && (v = SymbolicUtils.unwrap_const(v))
    v isa Number ? ComplexF64(v) : error("not a number: $e")
end
antiderivative(f) = RI.integrate(unwrap(f), unwrap(x))
# a definite integral: RischIntegrate's antiderivative at the bounds, by substitution where it is finite, else by
# Symbolics.limit
function definite(f, lo, hi)
    F = Num(RI.integrate(unwrap(f), unwrap(x)))
    at(bound) = begin
        if isfinite(bound)
            val = Symbolics.substitute(F, Dict(x => bound))
            vv = tonum(EVAL(val, Dict{Symbol,Float64}()))
            (vv !== nothing && isfinite(vv)) && return val
        end
        Num(Symbolics.limit(unwrap(F), unwrap(x), bound))
    end
    at(hi) - at(lo)
end
lim(f, x0) = Symbolics.limit(unwrap(f), unwrap(x), x0)
roots(eq) = [cnum(r) for r in symbolic_solve(eq, x)]
system_solutions(eqs, vars) = [Tuple(cnum(d[v]) for v in vars) for d in symbolic_solve(eqs, vars)]

# a linear ODE y^(n) + p_{n-1} y^(n-1) + ... + p_0 y = rhs (SymbolicLinearODE, as in its docstring), then the
# residual with every constant set to 1
SymbolicUtils.@syms 𝑦ᵉ(x)::Real
@variables 𝑦
Dx = Differential(x)
function linear_ode(p_coeffs, rhs, residual)
    eq = SymbolicLinearODE(𝑦, x, p_coeffs, rhs)
    sol = symbolic_solve_ode(eq)
    sol === nothing && return nothing
    post = () -> [Symbolics.simplify(expand_derivatives(residual(Symbolics.substitute(sol, Dict(cc => 1 for cc in eq.C)))))]
    (sol, post)
end

# the Brusselator on a ring of N cells (state order u1, v1, ..., uN, vN), its Jacobian by Symbolics.jacobian, compiled by
# build_function
function jacobian_fn(N)
    U = [Symbolics.variable(Symbol("u$i")) for i in 1:N]; V = [Symbolics.variable(Symbol("v$i")) for i in 1:N]
    eqs = Num[]; vars = Num[]
    for i in 1:N
        ip, im = mod1(i + 1, N), mod1(i - 1, N)
        push!(eqs, 1 + U[i]^2 * V[i] - 4U[i] + (U[ip] - 2U[i] + U[im]))
        push!(eqs, 3U[i] - U[i]^2 * V[i] + (V[ip] - 2V[i] + V[im]))
        push!(vars, U[i]); push!(vars, V[i])
    end
    f = Symbolics.build_function(Symbolics.jacobian(eqs, vars), vars; expression = Val(false))[1]
    w -> f(w)
end
function jacobian_eval(N)
    f = jacobian_fn(N)
    acc = 0.0
    for kk in 1:1000
        w = vec(permutedims(hcat([0.1i + 0.001kk for i in 1:N], [0.2i + 0.002kk for i in 1:N])))
        M = f(w)
        for i in 1:2N
            acc += M[i, i]
        end
    end
    acc
end

const TASKS = Dict{String,Any}(
    # antiderivatives
    "x^3 e^(2x)" => () -> antiderivative(x^3 * exp(2x)),
    "1/(x^3+1)" => () -> antiderivative(1 / (x^3 + 1)),
    "sec^3 x" => () -> antiderivative(sec(x)^3),
    "x/(x^4+1)" => () -> antiderivative(x / (x^4 + 1)),
    "ln(x)^2/x^2" => () -> antiderivative(log(x)^2 / x^2),
    "e^x sin x" => () -> antiderivative(exp(x) * sin(x)),
    "sqrt(1-x^2)" => () -> antiderivative(sqrt(1 - x^2)),
    "1/(x sqrt(x^2-1))" => () -> antiderivative(1 / (x * sqrt(x^2 - 1))),
    "x asin x" => () -> antiderivative(x * asin(x)),
    "1/(2+cos x)" => () -> antiderivative(1 / (2 + cos(x))),
    # definite integrals
    "Dalzell's integral" => () -> definite(x^4 * (1 - x)^4 / (1 + x^2), 0, 1),
    "Dirichlet's integral" => () -> definite(sin(x) / x, 0, Inf),
    "The Gaussian integral" => () -> definite(exp(-x^2), 0, Inf),
    "A logarithm over 1-x" => () -> definite(log(x) / (1 - x), 0, 1),
    "A power of the sine" => () -> definite(sin(x)^4, 0, pi),
    "Planck's integral" => () -> definite(x^3 / (exp(x) - 1), 0, Inf),
    "x ln(1+x) on [0,1]" => () -> definite(x * log(1 + x), 0, 1),
    "A quartic denominator on the line" => () -> definite(1 / (x^4 + 1), -Inf, Inf),
    "A damped sine" => () -> definite(x * exp(-x) * sin(x), 0, Inf),
    # series and products: Symbolics has no symbolic summation or product
    "zeta(6)" => missing, "n^3/3^n" => missing, "The alternating harmonic series" => missing, "A telescoping sum" => missing,
    "Leibniz's series" => missing, "The binomial theorem at 2" => missing, "Nicomachus's theorem" => missing,
    "1/(4n^2-1)" => missing, "A product equal to 2" => missing,
    # limits
    "(e^x-1-x)/x^2" => () -> lim((exp(x) - 1 - x) / x^2, 0),
    "(1-cos x)/x^2" => () -> lim((1 - cos(x)) / x^2, 0),
    "(1+2/x)^x" => () -> lim((1 + 2 / x)^x, Inf),
    "x^x at 0" => () -> lim(x^x, 0),
    "(sin x - x)/x^3" => () -> lim((sin(x) - x) / x^3, 0),
    "n(2^(1/n)-1)" => () -> Symbolics.limit(unwrap(n * (2^(1 / n) - 1)), unwrap(n), Inf),
    "sqrt(x^2+x)-x" => () -> lim(sqrt(x^2 + x) - x, Inf),
    "(tan x - x)/x^3" => () -> lim((tan(x) - x) / x^3, 0),
    "1/x - 1/(e^x-1)" => () -> lim(1 / x - 1 / (exp(x) - 1), 0),
    # equations and inequalities
    "A cubic with integer roots" => () -> roots(x^3 - 6x^2 + 11x - 6 ~ 0),
    "Sum and product" => () -> system_solutions([x + y - 5, x * y - 6], [x, y]),
    "A biquadratic" => () -> roots(x^4 - 10x^2 + 1 ~ 0),
    "An exponential equation" => () -> roots(2^x ~ 3^(x - 1)),
    "A circle and a line" => () -> system_solutions([x^2 + y^2 - 25, x - y - 1], [x, y]),
    "A cubic with one real root" => () -> roots(x^3 + x - 1 ~ 0),
    "A quadratic inequality" => missing, "An absolute value inequality" => missing,
    # polynomials
    "x^8-1 over Q" => () -> FACTOR(x^8 - 1),
    "Sophie Germain's identity" => () -> FACTOR(x^4 + 4),
    "x^3+y^3+z^3-3xyz" => () -> FACTOR(x^3 + y^3 + z^3 - 3x * y * z),
    "A polynomial gcd" => missing, "A resultant" => missing, "A discriminant" => missing,
    "A partial fraction decomposition" => () -> partial_frac_decomposition(1 / ((x - 1) * (x + 2)^2), x),
    "Two conics" => () -> system_solutions([x^2 + y^2 - 1, x * y - 1 // 4], [x, y]),
    # simplification
    "A nested radical" => () -> Symbolics.simplify(sqrt(7 + 4sqrt(Num(3))) - 2 - sqrt(Num(3))),
    "The Pythagorean identity" => () -> Symbolics.simplify(sin(x)^2 + cos(x)^2 - 1),
    "A removable singularity" => () -> Symbolics.simplify((x^3 - 1) / (x - 1) - x^2 - x - 1),
    "The golden cosine" => () -> Symbolics.simplify(cos(VAR[:pi] / 5) - (1 + sqrt(Num(5))) / 4),
    "tan(pi/12)" => () -> Symbolics.simplify(tan(VAR[:pi] / 12) - 2 + sqrt(Num(3))),
    "A minimal polynomial of degree six" => missing,
    "An exponential of a logarithm" => () -> Symbolics.simplify(exp(2log(x)) - x^2),
    "Zero identity: nested square root" => () -> Symbolics.simplify(sqrt(3 + 2sqrt(Num(2))) - 1 - sqrt(Num(2))),
    "Zero identity: nested cube root" => () -> Symbolics.simplify((7 + 5sqrt(Num(2)))^(Num(1) / 3) - 1 - sqrt(Num(2))),
    "Zero identity: logarithms on positive reals" => () -> Symbolics.simplify(log(Num(2)) + log(Num(3)) - log(Num(6))),
    "Zero identity: exponential of a logarithm" => () -> Symbolics.simplify(exp(log(Num(2))) - 2),
    "Zero identity: sine at pi over six" => () -> Symbolics.simplify(sin(VAR[:pi] / 6) - Num(1) / 2),
    "Nonzero control: rational residual" => () -> Symbolics.simplify(sqrt(Num(2))^2 - 2 + Num(1) / Num(big(10)^30)),
    "Nonzero control: near integer" => () -> Symbolics.simplify(exp(VAR[:pi] * sqrt(Num(163))) - Num(262537412640768744)),
    # differential equations (linear ones; Symbolics has no solver for y' = y^2)
    "A harmonic oscillator" => () -> linear_ode([4, 0], 0, y1 -> Dx(Dx(y1)) + 4y1),
    "A forced linear equation" => () -> linear_ode([2, -3], exp(3x), y1 -> Dx(Dx(y1)) - 3Dx(y1) + 2y1 - exp(3x)),
    "A first-order linear equation" => () -> linear_ode([2x], x, y1 -> Dx(y1) + 2x * y1 - x),
    "A first-order Euler equation" => () -> linear_ode([-1 / x], x, y1 -> x * Dx(y1) - y1 - x^2),
    "A polynomial forcing" => () -> linear_ode([1, 0], x, y1 -> Dx(Dx(y1)) + y1 - x),
    "A separable equation" => missing,
    "An initial-value problem" => () -> begin
        sol = Symbolics.laplace_solve_ode(Dx(Dx(𝑦ᵉ(x))) + Dx(𝑦ᵉ(x)) - 2𝑦ᵉ(x) ~ 0, 𝑦ᵉ, x, [1, 0])
        sol === nothing && return nothing
        post = () -> [Symbolics.simplify(expand_derivatives(Dx(Dx(sol)) + Dx(sol) - 2sol)),
                      Symbolics.substitute(sol, Dict(x => 0)) - 1, Symbolics.substitute(expand_derivatives(Dx(sol)), Dict(x => 0))]
        (sol, post)
    end,
    "A repeated characteristic root" => () -> linear_ode([1, -2], 0, y1 -> Dx(Dx(y1)) - 2Dx(y1) + y1),
    # linear algebra
    "A tridiagonal determinant" => () -> det(Num[2 1 0; 1 2 1; 0 1 2]),
    "A 2x2 inverse" => () -> fl.(inv(Num[4 7; 2 6])),
    "Eigenvalues of a symmetric matrix" => missing, "The rank of a singular matrix" => missing,
    "A linear system" => () -> fl.(symbolic_linear_solve([2x + y - z ~ 8, -3x - y + 2z ~ -11, -2x + y + 2z ~ -3], [x, y, z])),
    "A characteristic polynomial" => () -> Symbolics.expand(det(x * I - Num[1 2; 3 4])),
    "A Fibonacci matrix power" => () -> fl.(Num[1 1; 1 0]^10),
    "A symbolic determinant" => () -> det([a b; b a]),
    # number theory (Primes.jl, to which Symbolics.factor forwards integers)
    "The Fermat number F6" => () -> sort([big(pp) for (pp, _) in Primes.factor(big(2)^64 + 1)]),
    "A Mersenne prime of 89 bits" => () -> Primes.isprime(big(2)^89 - 1),
    "A gcd of Mersenne numbers" => missing, "A modular inverse" => missing, "Euler's totient of a million" => missing,
    "The next prime after 10^12" => missing, "The Chinese remainder theorem" => missing, "A sum of divisors" => missing,
    # transforms and series expansions
    "A Laplace transform" => () -> LAPLACE(t * exp(-2t), t, s),
    "An inverse Laplace transform" => () -> ILAPLACE(1 / (s^2 + 4), s, t),
    "The Laplace transform of a cosine" => () -> LAPLACE(cos(2t), t, s),
    "Gamma at one half" => () -> Symbolics.simplify(SpecialFunctions.gamma(Num(1 // 2))),
    "A Beta value" => () -> Symbolics.simplify(SpecialFunctions.beta(Num(2), Num(3))),
    "Gamma at five halves" => () -> Symbolics.simplify(SpecialFunctions.gamma(Num(5 // 2))),
    "The series of tan" => () -> taylor(tan(x), x, 0:7),
    "The series of e^x sin x" => () -> taylor(exp(x) * sin(x), x, 0:5),
    # model to Jacobian
    "Jacobian: Brusselator N=10 (build)" => () -> jacobian_fn(10),
    "Jacobian: Brusselator N=50 (build)" => () -> jacobian_fn(50),
    "Jacobian: Brusselator N=10 (evaluate 1000 points)" => () -> jacobian_eval(10),
    "Jacobian: Brusselator N=50 (evaluate 1000 points)" => () -> jacobian_eval(50),
)
