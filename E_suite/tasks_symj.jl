# Bench E tasks for SymJ.jl (with RischIntegrate.jl for integrals and
# GruntzLimit.jl for limits, as in SymJ's own CAS comparison), written for this
# repository. An operation SymJ does not define in the pinned version is
# `missing` (unavailable), found by name at load time. A task returns the answer,
# or (answer, post) with post() a residual computed outside the timed call.
using LinearAlgebra: det, I
const x, y, z, t, s, a, b, n, k, p, q = (VAR[vv] for vv in (:x, :y, :z, :t, :s, :a, :b, :n, :k, :p, :q))
fl(e) = Float64(real(N(e)))
cx(e) = ComplexF64(N(e))
whenop(f, g) = f === missing ? missing : g
antiderivative(f) = RischIntegrate.integrate(f, x)
definite(f, lo, hi) = RischIntegrate.integrate(f, (x, lo, hi))
const summation = getop(:summation)
const sproduct = getop(:product)
const dsolve = getop(:dsolve)
const series_ = getop(:series)
const resultant_ = getop(:resultant)
const minpoly_ = getop(:minpoly)
const discriminant_ = getop(:discriminant)
const apart_ = getop(:apart)
const eigvals_ = getop(:eigvals)
const rank_ = getop(:rank)
const jacobian_ = getop(:jacobian)
const laplace_ = getop(:laplace)
const ilaplace_ = getop(:ilaplace)
roots(eq) = [cx(r) for r in generic(solve(eq, x))]
system_solutions(eqs, vars) = [Tuple(cx(d[v]) for v in vars) for d in generic(solve(eqs, vars))]

# an ODE by dsolve, then the residuals with every constant set to 1
@syms yy()
function ode(eq, residuals::Vector; ics = ())
    sol = dsolve(eq, yy(x), ics...)
    rhs = sol isa SymJ.Relation ? sol.rhs : sol
    post = () -> begin
        cs = [cc for cc in free_symbols(rhs) if !(cc in (x, a))]
        y1 = isempty(cs) ? rhs : subs(rhs, (cc => 1 for cc in cs)...)
        [simplify(res(y1)) for res in residuals]
    end
    (rhs, post)
end

# the Brusselator on a ring of N cells (state order u1, v1, ..., uN, vN), its Jacobian by SymJ, compiled by lambdify
function jacobian_fn(N)
    U = [Sym(Symbol("u$i")) for i in 1:N]; V = [Sym(Symbol("v$i")) for i in 1:N]
    eqs = Sym[]; vars = Sym[]
    for i in 1:N
        ip, im = mod1(i + 1, N), mod1(i - 1, N)
        push!(eqs, 1 + U[i]^2 * V[i] - 4U[i] + (U[ip] - 2U[i] + U[im]))
        push!(eqs, 3U[i] - U[i]^2 * V[i] + (V[ip] - 2V[i] + V[im]))
        push!(vars, U[i]); push!(vars, V[i])
    end
    f = lambdify(jacobian_(eqs, vars), vars...)
    w -> f(w...)
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
    "A power of the sine" => () -> definite(sin(x)^4, 0, Sym(π)),
    "Planck's integral" => () -> definite(x^3 / (exp(x) - 1), 0, Inf),
    "x ln(1+x) on [0,1]" => () -> definite(x * log(1 + x), 0, 1),
    "A quartic denominator on the line" => () -> definite(1 / (x^4 + 1), -Inf, Inf),
    "A damped sine" => () -> definite(x * exp(-x) * sin(x), 0, Inf),
    # series and products
    "zeta(6)" => whenop(summation, () -> summation(1 / n^6, (n, 1, Inf))),
    "n^3/3^n" => whenop(summation, () -> summation(n^3 / Sym(3)^n, (n, 1, Inf))),
    "The alternating harmonic series" => whenop(summation, () -> summation((-1)^(n + 1) / n, (n, 1, Inf))),
    "A telescoping sum" => whenop(summation, () -> summation(1 / (n * (n + 1) * (n + 2)), (n, 1, Inf))),
    "Leibniz's series" => whenop(summation, () -> summation((-1)^n / (2n + 1), (n, 0, Inf))),
    "The binomial theorem at 2" => whenop(summation, () -> summation(binomial(n, k) * Sym(2)^k, (k, 0, n))),
    "Nicomachus's theorem" => whenop(summation, () -> summation(k^3, (k, 1, n))),
    "1/(4n^2-1)" => whenop(summation, () -> summation(1 / (4n^2 - 1), (n, 1, Inf))),
    "A product equal to 2" => whenop(sproduct, () -> sproduct((n + 1)^2 / (n * (n + 2)), (n, 1, Inf))),
    # limits
    "(e^x-1-x)/x^2" => () -> limit((exp(x) - 1 - x) / x^2, x => 0),
    "(1-cos x)/x^2" => () -> limit((1 - cos(x)) / x^2, x => 0),
    "(1+2/x)^x" => () -> limit((1 + 2 / x)^x, x => Inf),
    "x^x at 0" => () -> limit(x^x, x => 0),
    "(sin x - x)/x^3" => () -> limit((sin(x) - x) / x^3, x => 0),
    "n(2^(1/n)-1)" => () -> limit(n * (Sym(2)^(1 / n) - 1), n => Inf),
    "sqrt(x^2+x)-x" => () -> limit(sqrt(x^2 + x) - x, x => Inf),
    "(tan x - x)/x^3" => () -> limit((tan(x) - x) / x^3, x => 0),
    "1/x - 1/(e^x-1)" => () -> limit(1 / x - 1 / (exp(x) - 1), x => 0),
    # equations and inequalities
    "A cubic with integer roots" => () -> roots(x^3 - 6x^2 + 11x - 6 ~ 0),
    "Sum and product" => () -> system_solutions([x + y ~ 5, x * y ~ 6], [x, y]),
    "A biquadratic" => () -> roots(x^4 - 10x^2 + 1 ~ 0),
    "An exponential equation" => () -> roots(Sym(2)^x ~ Sym(3)^(x - 1)),
    "A circle and a line" => () -> system_solutions([x^2 + y^2 ~ 25, x - y ~ 1], [x, y]),
    "A cubic with one real root" => () -> roots(x^3 + x - 1 ~ 0),
    "A quadratic inequality" => () -> solve(x^2 - 3x + 2 ≪ 0, x),
    "An absolute value inequality" => () -> solve(abs(2x - 3) ≪ 5, x),
    # polynomials
    "x^8-1 over Q" => () -> FACTOR(x^8 - 1),
    "Sophie Germain's identity" => () -> FACTOR(x^4 + 4),
    "x^3+y^3+z^3-3xyz" => () -> FACTOR(x^3 + y^3 + z^3 - 3x * y * z),
    "A polynomial gcd" => () -> gcd(x^4 - 1, x^6 - 1),
    "A resultant" => whenop(resultant_, () -> resultant_(x^2 + y^2 - 1, x - y, y)),
    "A discriminant" => whenop(discriminant_, () -> discriminant_(x^3 + p * x + q, x)),
    "A partial fraction decomposition" => whenop(apart_, () -> apart_(1 / ((x - 1) * (x + 2)^2), x)),
    "Two conics" => () -> system_solutions([x^2 + y^2 ~ 1, x * y ~ Sym(1) / 4], [x, y]),
    # simplification
    "A nested radical" => () -> simplify(sqrt(7 + 4sqrt(Sym(3))) - 2 - sqrt(Sym(3))),
    "The Pythagorean identity" => () -> simplify(sin(x)^2 + cos(x)^2 - 1),
    "A removable singularity" => () -> simplify((x^3 - 1) / (x - 1) - x^2 - x - 1),
    "The golden cosine" => () -> simplify(cos(Sym(π) / 5) - (1 + sqrt(Sym(5))) / 4),
    "tan(pi/12)" => () -> simplify(tan(Sym(π) / 12) - 2 + sqrt(Sym(3))),
    "A minimal polynomial of degree six" => whenop(minpoly_, () -> minpoly_(sqrt(Sym(2)) + Sym(3)^(Sym(1) / 3), x)),
    "An exponential of a logarithm" => () -> simplify(exp(2log(x)) - x^2),
    "Zero identity: nested square root" => () -> simplify(sqrt(3 + 2sqrt(Sym(2))) - 1 - sqrt(Sym(2))),
    "Zero identity: nested cube root" => () -> simplify((7 + 5sqrt(Sym(2)))^(Sym(1) / 3) - 1 - sqrt(Sym(2))),
    "Zero identity: logarithms on positive reals" => () -> simplify(log(Sym(2)) + log(Sym(3)) - log(Sym(6))),
    "Zero identity: exponential of a logarithm" => () -> simplify(exp(log(Sym(2))) - 2),
    "Zero identity: sine at pi over six" => () -> simplify(sin(Sym(π) / 6) - Sym(1) / 2),
    "Nonzero control: rational residual" => () -> simplify(sqrt(Sym(2))^2 - 2 + Sym(1) / Sym(big(10)^30)),
    "Nonzero control: near integer" => () -> simplify(exp(Sym(π) * sqrt(Sym(163))) - Sym(262537412640768744)),
    # differential equations
    "A harmonic oscillator" => whenop(dsolve, () -> ode(diff(yy(x), x, x) + 4yy(x) ~ 0, [y1 -> diff(y1, x, x) + 4y1])),
    "A forced linear equation" => whenop(dsolve, () -> ode(diff(yy(x), x, x) - 3diff(yy(x), x) + 2yy(x) ~ exp(3x),
                                                         [y1 -> diff(y1, x, x) - 3diff(y1, x) + 2y1 - exp(3x)])),
    "A first-order linear equation" => whenop(dsolve, () -> ode(diff(yy(x), x) + 2x * yy(x) ~ x, [y1 -> diff(y1, x) + 2x * y1 - x])),
    "A first-order Euler equation" => whenop(dsolve, () -> ode(x * diff(yy(x), x) - yy(x) ~ x^2, [y1 -> x * diff(y1, x) - y1 - x^2])),
    "A polynomial forcing" => whenop(dsolve, () -> ode(diff(yy(x), x, x) + yy(x) ~ x, [y1 -> diff(y1, x, x) + y1 - x])),
    "A separable equation" => whenop(dsolve, () -> ode(diff(yy(x), x) ~ yy(x)^2, [y1 -> diff(y1, x) - y1^2])),
    "An initial-value problem" => whenop(dsolve, () -> ode(diff(yy(x), x, x) + diff(yy(x), x) - 2yy(x) ~ 0,
        [y1 -> diff(y1, x, x) + diff(y1, x) - 2y1, y1 -> subs(y1, x => 0) - 1, y1 -> subs(diff(y1, x), x => 0)];
        ics = (yy(0) => 1, diff(yy(x), x)(0) => 0))),
    "A repeated characteristic root" => whenop(dsolve, () -> ode(diff(yy(x), x, x) - 2diff(yy(x), x) + yy(x) ~ 0, [y1 -> diff(y1, x, x) - 2diff(y1, x) + y1])),
    # linear algebra
    "A tridiagonal determinant" => () -> det(Sym[2 1 0; 1 2 1; 0 1 2]),
    "A 2x2 inverse" => () -> fl.(inv(Sym[4 7; 2 6])),
    "Eigenvalues of a symmetric matrix" => whenop(eigvals_, () -> [fl(e) for e in eigvals_(Sym[2 1; 1 2])]),
    "The rank of a singular matrix" => whenop(rank_, () -> rank_(Sym[1 2 3; 4 5 6; 7 8 9])),
    "A linear system" => () -> (d = only(generic(solve([2x + y - z ~ 8, -3x - y + 2z ~ -11, -2x + y + 2z ~ -3], [x, y, z]))); [fl(d[x]), fl(d[y]), fl(d[z])]),
    "A characteristic polynomial" => () -> expand(det(x * I(2) - Sym[1 2; 3 4])),
    "A Fibonacci matrix power" => () -> fl.(Sym[1 1; 1 0]^10),
    "A symbolic determinant" => () -> det(Sym[a b; b a]),
    # number theory, where SymJ defines the operation
    "The Fermat number F6" => whenop(getop(:factorint), () -> sort([parse(BigInt, string(pp)) for pp in keys(getop(:factorint)(Sym(big(2)^64 + 1)))])),
    "A Mersenne prime of 89 bits" => whenop(getop(:isprime), () -> getop(:isprime)(Sym(big(2)^89 - 1))),
    "A gcd of Mersenne numbers" => () -> gcd(Sym(big(2)^60 - 1), Sym(big(2)^84 - 1)),
    "A modular inverse" => missing,                     # invmod is Julia's own, with no method for Sym
    "Euler's totient of a million" => whenop(getop(:totient), () -> getop(:totient)(Sym(10^6))),
    "The next prime after 10^12" => whenop(getop(:nextprime), () -> getop(:nextprime)(Sym(10^12))),
    "The Chinese remainder theorem" => whenop(getop(:crt), () -> first(getop(:crt)([3, 5, 7], [2, 3, 2]))),
    "A sum of divisors" => whenop(getop(:divisor_sigma), () -> getop(:divisor_sigma)(Sym(360))),
    # transforms and series expansions
    "A Laplace transform" => whenop(laplace_, () -> laplace_(t * exp(-2t), t, s)),
    "An inverse Laplace transform" => whenop(ilaplace_, () -> ilaplace_(1 / (s^2 + 4), s, t)),
    "The Laplace transform of a cosine" => whenop(laplace_, () -> laplace_(cos(2t), t, s)),
    "Gamma at one half" => () -> simplify(SpecialFunctions.gamma(Sym(1) / 2)),
    "A Beta value" => () -> simplify(SpecialFunctions.beta(Sym(2), Sym(3))),
    "Gamma at five halves" => () -> simplify(SpecialFunctions.gamma(Sym(5) / 2)),
    "The series of tan" => whenop(series_, () -> series_(tan(x), x, 0, 8)),
    "The series of e^x sin x" => whenop(series_, () -> series_(exp(x) * sin(x), x, 0, 6)),
    # model to Jacobian
    "Jacobian: Brusselator N=10 (build)" => whenop(jacobian_, () -> jacobian_fn(10)),
    "Jacobian: Brusselator N=50 (build)" => whenop(jacobian_, () -> jacobian_fn(50)),
    "Jacobian: Brusselator N=10 (evaluate 1000 points)" => whenop(jacobian_, () -> jacobian_eval(10)),
    "Jacobian: Brusselator N=50 (evaluate 1000 points)" => whenop(jacobian_, () -> jacobian_eval(50)),
)
