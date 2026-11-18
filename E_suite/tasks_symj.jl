# Bench E tasks for SymJ.jl 0.1.0 (with GruntzLimit and RischIntegrate).
# Operations are looked up by name in SymJ at load time (getop): a name that
# does not exist is reported as unavailable, a call that raises as an error.
using LinearAlgebra: det, rank
C6 = [Sym(Symbol("c$i")) for i in 1:6]
for i in 1:6
    VAR[Symbol("c$i")] = C6[i]
end
const th, p, q, r, px, py = Sym(:th), Sym(:p), Sym(:q), Sym(:r), Sym(:px), Sym(:py)
const x, y, z, t, s, a, b, c, k, n, u, v = (VAR[vv] for vv in (:x, :y, :z, :t, :s, :a, :b, :c, :k, :n, :u, :v))
fl(e) = Float64(real(N(e)))
cx(e) = ComplexF64(N(e))
risch(f) = RischIntegrate.integrate(f, x)
def(f, lo, hi) = RischIntegrate.integrate(f, (x, lo, hi))
summation = getop(:summation)
series_ = getop(:series)
dsolve = getop(:dsolve)
groebner = getop(:groebner)
resultant = getop(:resultant)
minpoly = getop(:minpoly)
jac = getop(:jacobian)
whenop(f, g) = f === missing ? missing : g
@syms yy() ff()
# dsolve(eq, y(x), ics...) returns y(x) ~ solution; the residuals with the constants set to 1
function ode(eq, residuals::Vector; var = x, ics = ())
    sol = dsolve(eq, yy(var), ics...)
    rhs = sol isa SymJ.Relation ? sol.rhs : sol
    post = () -> begin
        cs = [c for c in free_symbols(rhs) if !(c in (x, t, a))]
        y1 = isempty(cs) ? rhs : subs(rhs, (c => 1 for c in cs)...)
        [simplify(res(y1)) for res in residuals]
    end
    (rhs, post)
end
cyclic6() = begin
    polys = Sym[]
    for m in 1:5
        push!(polys, sum(prod(C6[mod1(kk + j, 6)] for j in 0:m-1) for kk in 1:6))
    end
    push!(polys, prod(C6) - 1)
    polys
end
function bruss(N)
    U = [Sym(Symbol("u$i")) for i in 1:N]; V = [Sym(Symbol("v$i")) for i in 1:N]
    eqs = Sym[]; vars = Sym[]
    for i in 1:N
        ip, im = mod1(i + 1, N), mod1(i - 1, N)
        push!(eqs, 1 + U[i]^2 * V[i] - 4U[i] + (U[ip] - 2U[i] + U[im])); push!(eqs, 3U[i] - U[i]^2 * V[i] + (V[ip] - 2V[i] + V[im]))
        push!(vars, U[i]); push!(vars, V[i])
    end
    eqs, vars
end
function jacobian_fn(N)
    eqs, vars = bruss(N)
    J = jac(eqs, vars)
    f = lambdify(J, vars...)
    w -> f(w...)
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
    "A fourth root" => () -> risch(1 / (1 + x^4)^(Sym(1) / 4)),
    "Parts, twice" => () -> risch(x^2 * asin(x)^2),
    "Exponential and logarithm (Risch)" => () -> risch(exp(x) * (1 + x * log(x)) / x),
    "A Bessel function, to Struve functions" => () -> risch(x^2 * SpecialFunctions.besselj0(x)),
    "The error function squared" => () -> risch(SpecialFunctions.erf(x)^2),
    "Bose-Einstein type" => () -> def(x / (exp(x) - 1), 0, Inf),
    "Serret's integral" => () -> def(log(1 + x) / (1 + x^2), 0, 1),
    "A symmetry trick" => () -> def(x * sin(x) / (1 + cos(x)^2), 0, Sym(π)),
    "Log-sine" => () -> def(log(sin(x)), 0, Sym(π) / 2),
    "Ahmed's integral" => () -> def(atan(sqrt(x^2 + 2)) / ((x^2 + 1) * sqrt(x^2 + 2)), 0, 1),
    "Laplace's integral" => () -> def(cos(x) / (1 + x^2), 0, Inf),
    "A dilogarithm value" => () -> def(log(x) * log(1 - x), 0, 1),
    "Euler's constant" => () -> def(exp(-x) * log(x)^2, 0, Inf),
    "A Gaussian with a cosine" => () -> def(exp(-x^2) * cos(2x), -Inf, Inf),
    "Frullani's integral" => () -> def((exp(-x) - exp(-2x)) / x, 0, Inf),
    "The error function" => () -> def(SpecialFunctions.erfc(x)^2, 0, Inf),
    "A Bessel function on the half-line" => () -> def(SpecialFunctions.besselj0(x), 0, Inf),
    "A damped Bessel function" => () -> def(exp(-x) * SpecialFunctions.besselj0(x), 0, Inf),
    "A pendulum's period" => () -> def(1 / sqrt(cos(x) - cos(a)), 0, a),
    "zeta(4)" => whenop(summation, () -> summation(1 / n^4, (n, 1, Inf))),
    "Harmonic numbers" => whenop(summation, () -> summation(summation(1 / k, (k, 1, n)) / n^2, (n, 1, Inf))),
    "Dirichlet beta(3)" => whenop(summation, () -> summation((-1)^n / (2n + 1)^3, (n, 0, Inf))),
    "Arithmetic-geometric" => whenop(summation, () -> summation(n^2 / 2^n, (n, 1, Inf))),
    "A central binomial series" => whenop(summation, () -> summation(1 / (n^2 * binomial(2n, n)), (n, 1, Inf))),
    "Vandermonde's identity" => whenop(summation, () -> summation(binomial(n, k)^2, (k, 0, n))),
    "A closed form in n" => whenop(summation, () -> summation(k * 2^k, (k, 1, n))),
    "A polylogarithm value" => whenop(summation, () -> subs(summation(x^n / n^2, (n, 1, Inf)), x => Sym(1) / 2)),
    "A telescoping product" => whenop(getop(:product), () -> getop(:product)(1 - 1 / n^2, (n, 2, Inf))),
    "Wallis's product" => whenop(getop(:product), () -> getop(:product)(4n^2 / (4n^2 - 1), (n, 1, Inf))),
    "tan sin - sin tan" => () -> limit((tan(sin(x)) - sin(tan(x))) / x^7, x => 0),
    "Stirling" => () -> limit(factorial(n)^(1 / n) / n, n => Inf),
    "A second-order term of e" => () -> limit(x * ((1 + 1 / x)^x - exp(Sym(1))), x => Inf),
    "Nested exponentials (Gruntz)" => () -> limit(exp(x) * (exp(1 / x - exp(-x)) - exp(1 / x)), x => Inf),
    "Cancelling poles" => () -> limit(1 / x^2 - 1 / sin(x)^2, x => 0),
    "A ratio of Gamma functions" => () -> limit(SpecialFunctions.gamma(x + Sym(1) / 2) / (SpecialFunctions.gamma(x) * sqrt(x)), x => Inf),
    "A power of sinc" => () -> limit((sin(x) / x)^(1 / x^2), x => 0),
    "A bounded oscillation" => () -> limit((x + sin(x)) / x, x => Inf),
    "A sextic system" => () -> [(cx(d[x]), cx(d[y])) for d in generic(solve([x^2 + y^2 ~ 1, x^3 ~ y], [x, y]))],
    "A quintic solvable by radicals" => () -> solve(x^5 - 5x + 12 ~ 0, x),
    "Every solution of cos x = 1/2" => () -> solve(cos(x) ~ Sym(1) / 2, x),
    "Lambert's W" => () -> solve(x * exp(x) ~ 2, x),
    "A symmetric system" => () -> [(cx(d[x]), cx(d[y]), cx(d[z])) for d in generic(solve([x + y + z ~ 6, x * y + y * z + z * x ~ 11, x * y * z ~ 6], [x, y, z]))],
    "A quartic inequality" => () -> solve(x^4 - 5x^2 + 4 < 0, x),
    "Absolute values" => () -> solve(abs(x - 1) + abs(x + 2) < 5, x),
    "Quantifier elimination" => missing,
    "Cyclotomic factors" => () -> FACTOR(x^105 - 1),
    "A symmetric septic" => () -> FACTOR((x + y + z)^7 - x^7 - y^7 - z^7),
    "Factoring over Q(sqrt 2)" => missing,
    "The cyclic-6 system" => missing,
    "Implicitization" => whenop(resultant, () -> resultant(x - t^2 + 1, y - t^3 + t, t)),
    "Polynomial decomposition" => missing,
    "Denesting" => () -> simplify(sqrt(5 + 2sqrt(Sym(6)))),
    "Ramanujan's denesting" => () -> simplify((Sym(2)^(Sym(1) / 3) - 1)^(Sym(1) / 3)),
    "A heptagon sum" => () -> simplify(cos(2Sym(π) / 7) + cos(4Sym(π) / 7) + cos(6Sym(π) / 7)),
    "A minimal polynomial" => whenop(minpoly, () -> minpoly(sqrt(Sym(2)) + sqrt(Sym(3)) + sqrt(Sym(5)), x)),
    "A trigonometric identity" => () -> simplify(sin(3x) / sin(x) - cos(3x) / cos(x)),
    "Gauss's 17-gon" => missing, "An inverse cosine, with assumptions" => missing,
    "Airy" => whenop(dsolve, () -> ode(diff(yy(x), x, x) ~ x * yy(x), [y1 -> diff(y1, x, x) - x * y1])),
    "Bessel, order 1/2" => whenop(dsolve, () -> ode(x^2 * diff(yy(x), x, x) + x * diff(yy(x), x) + (x^2 - Sym(1) / 4) * yy(x) ~ 0, [y1 -> x^2 * diff(y1, x, x) + x * diff(y1, x) + (x^2 - Sym(1) / 4) * y1])),
    "Riccati" => whenop(dsolve, () -> ode(diff(yy(x), x) ~ x^2 + yy(x)^2, [y1 -> diff(y1, x) - x^2 - y1^2])),
    "A nonlinear autonomous equation" => whenop(dsolve, () -> ode(yy(x) * diff(yy(x), x, x) ~ diff(yy(x), x)^2, [y1 -> y1 * diff(y1, x, x) - diff(y1, x)^2])),
    "A forced Euler-Cauchy equation" => whenop(dsolve, () -> ode(x^2 * diff(yy(x), x, x) - 3x * diff(yy(x), x) + 4yy(x) ~ x^2 * log(x), [y1 -> x^2 * diff(y1, x, x) - 3x * diff(y1, x) + 4y1 - x^2 * log(x)])),
    "Bernoulli" => whenop(dsolve, () -> ode(diff(yy(x), x) + yy(x) ~ x * yy(x)^3, [y1 -> diff(y1, x) + y1 - x * y1^3])),
    "An exponential solution (Kovacic)" => whenop(dsolve, () -> ode(diff(yy(x), x, x) ~ (x^2 + 1) * yy(x), [y1 -> diff(y1, x, x) - (x^2 + 1) * y1])),
    "A forced initial-value problem" => whenop(dsolve, () -> ode(diff(yy(x), x, x) - (x^2 + 1) * yy(x) ~ x * exp(-x^2 / 2),
        [y1 -> diff(y1, x, x) - (x^2 + 1) * y1 - x * exp(-x^2 / 2), y1 -> subs(y1, x => 0), y1 -> subs(diff(y1, x), x => 0) - 1];
        ics = (yy(0) => 0, diff(yy(x), x)(0) => 1))),
    "A Riccati equation with Airy solutions" => whenop(dsolve, () -> ode(diff(yy(x), x) ~ x + yy(x)^2, [y1 -> diff(y1, x) - x - y1^2])),
    "A pendulum released from rest" => whenop(dsolve, () -> ode(diff(yy(x), x, x) + sin(yy(x)) ~ 0, [y1 -> diff(y1, x, x) + sin(y1), y1 -> subs(y1, x => 0) - a, y1 -> subs(diff(y1, x), x => 0)]; ics = (yy(0) => a, diff(yy(x), x)(0) => 0))),
    "Duffing's oscillator from rest" => whenop(dsolve, () -> ode(diff(yy(x), x, x) + yy(x) + yy(x)^3 ~ 0, [y1 -> diff(y1, x, x) + y1 + y1^3, y1 -> subs(y1, x => 0) - a, y1 -> subs(diff(y1, x), x => 0)]; ics = (yy(0) => a, diff(yy(x), x)(0) => 0))),
    "A Jordan block" => missing,                 # no matrix exponential
    "The transport equation" => missing, "The heat equation" => missing,
    "Symbolic eigenvalues" => whenop(getop(:eigvals), () -> [fl(subs(e, a => Sym(13) / 10)) for e in getop(:eigvals)(Sym[a 1 0; 1 a 1; 0 1 a])]),
    "A Jordan form" => missing, "A matrix exponential" => missing,
    "A Vandermonde determinant" => () -> FACTOR(det(Sym[v^j for v in (a, b, x, y, z), j in 0:4])),
    "A Smith normal form" => missing,
    "The Fermat number F7" => missing, "A Mersenne prime" => missing, "A discrete logarithm" => missing,
    "Pell's equation" => missing, "A periodic continued fraction" => missing, "Partitions" => missing,
    "A Laplace transform" => whenop(getop(:laplace), () -> getop(:laplace)(t^2 * exp(-t) * sin(t), t, s)),
    "An inverse Laplace transform" => whenop(getop(:ilaplace), () -> getop(:ilaplace)(1 / (s^2 + 1)^2, s, t)),
    "A delayed step" => whenop(getop(:ilaplace), () -> getop(:ilaplace)(exp(-s) / s, s, t)),
    "The series of Lambert's W" => whenop(series_, () -> series_(getop(:lambertw)(x), x, 0, 6)),
    "A hypergeometric function" => missing,
    "Gamma's reflection formula" => () -> simplify(SpecialFunctions.gamma(Sym(1) / 4) * SpecialFunctions.gamma(Sym(3) / 4)),
    "The sine integral's Laplace transform" => missing, "An inverse Laplace transform to a Bessel function" => missing,
    "A polylogarithm value" => missing,
    "A stability region" => () -> solve([3 * 3 - (1 + k) > 0, 1 + k > 0], k),
    "A Lyapunov equation" => () -> (d = only(generic(solve([-4q + 1 ~ 0, p - 3q - 2r ~ 0, 2q - 6r + 1 ~ 0], [p, q, r]))); [fl(d[p]) fl(d[q]); fl(d[q]) fl(d[r])]),
    "A Riccati equation (LQR)" => () -> begin
        for d in generic(solve([-q^2 + 1 ~ 0, p - q * r ~ 0, 2q - r^2 + 1 ~ 0], [p, q, r]))
            pp, qq, rr = cx(d[p]), cx(d[q]), cx(d[r])
            (isreal(pp) && isreal(qq) && isreal(rr)) || continue
            pp, qq, rr = real(pp), real(qq), real(rr)
            pp > 0 && pp * rr - qq^2 > 0 && return [pp qq; qq rr]
        end
        nothing
    end,
    "The unicycle's Lie algebra rank" => whenop(jac, () -> begin
        f1 = [cos(th), sin(th), Sym(0)]; f2 = [Sym(0), Sym(0), Sym(1)]; X = [px, py, th]
        br = jac(f2, X) * f1 - jac(f1, X) * f2
        M = subs.(hcat(f1, f2, br), Ref(th => Sym(3) / 10))
        rank(Float64.(N.(M)))
    end),
    "A center manifold" => () -> begin
        c2, c3, c4 = Sym(:c2), Sym(:c3), Sym(:c4)
        h = c2 * x^2 + c3 * x^3 + c4 * x^4
        rr = expand(diff(h, x) * x * h + h + x^2)
        P = Poly(rr, x)
        d = only(generic(solve([coeff(P, 2) ~ 0, coeff(P, 3) ~ 0, coeff(P, 4) ~ 0], [c2, c3, c4])))
        subs(h, c2 => d[c2], c3 => d[c3], c4 => d[c4])
    end,
    "A sum-of-squares certificate" => missing, "Motzkin's polynomial" => missing,
    "Jacobian: Brusselator N=10 (build)" => whenop(jac, () -> jacobian_fn(10)),
    "Jacobian: Brusselator N=50 (build)" => whenop(jac, () -> jacobian_fn(50)),
    "Jacobian: Brusselator N=10 (evaluate 1000 points)" => whenop(jac, () -> jacobian_eval(10)),
    "Jacobian: Brusselator N=50 (evaluate 1000 points)" => whenop(jac, () -> jacobian_eval(50)),
)
