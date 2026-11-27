# Bench E tasks for SymPy through SymPyPythonCall.jl, written for this repository:
# each task makes the SymPy call a SymPy user would make. A task returns the
# answer, or (answer, post) with post() a residual computed outside the timed call.
const PyC = SymPyPythonCall.PythonCall
const PySympy = PyC.pyimport("sympy")
raw(e) = e isa Sym ? getfield(e, :o) : e            # the Python object behind a Sym
half = Sym(1) / 2
cnum(e) = ComplexF64(N(e))
fnum(e) = Float64(real(N(e)))
pyint(nn) = Sym(PyC.pyint(nn))                      # an exact integer of any size, as SymPy's Integer
# a SymPy Matrix from a Julia matrix, built on the Python side (rows of Python lists)
smat(M::AbstractMatrix) = Sym(PySympy.Matrix(PyC.pylist([PyC.pylist([raw(Sym(e)) for e in M[i, :]]) for i in 1:size(M, 1)])))
# SymPyPythonCall returns most SymPy matrices as Julia matrices of Sym; a power stays a SymPy matrix
jmat(M::AbstractMatrix) = [fnum(e) for e in M]
jmat(M::Sym) = reduce(vcat, [permutedims([fnum(Sym(e)) for e in row]) for row in raw(M).tolist()])
# lambdify inspects its caller's Python frame, which a call made straight from Julia does not have: it is called from
# a Python lambda
const pylambdify = PyC.pyeval("lambda a, e, m: __import__('sympy').lambdify(a, e, m)", @__MODULE__)
# the solutions of a system, a list of tuples from solve, as tuples of numbers
solution_tuples(sols) = [Tuple(cnum(c) for c in collect(t)) for t in collect(sols)]

const yf = S.Function("y")
# an ODE: dsolve, then the residuals with every constant C1, C2 set to 1
function ode(eq, residuals::Vector; ics = nothing)
    sol = ics === nothing ? S.dsolve(eq, yf(x)) : S.dsolve(eq, yf(x); ics = ics)
    sol isa AbstractVector && (sol = first(sol))
    rhs = sol.rhs
    post = () -> begin
        cs = [c for c in collect(free_symbols(rhs)) if startswith(string(c), "C")]
        y1 = isempty(cs) ? rhs : subs(rhs, (c => 1 for c in cs)...)
        [S.simplify(res(y1)) for res in residuals]
    end
    (rhs, post)
end

# the Brusselator on a ring of N cells (state order u1, v1, ..., uN, vN), its Jacobian by SymPy, compiled by lambdify
function jacobian_fn(N)
    U = [Sym("u$i") for i in 1:N]; V = [Sym("v$i") for i in 1:N]
    eqs = Sym[]; vars = Sym[]
    for i in 1:N
        ip, im = mod1(i + 1, N), mod1(i - 1, N)
        push!(eqs, 1 + U[i]^2 * V[i] - 4U[i] + (U[ip] - 2U[i] + U[im]))
        push!(eqs, 3U[i] - U[i]^2 * V[i] + (V[ip] - 2V[i] + V[im]))
        push!(vars, U[i]); push!(vars, V[i])
    end
    J = Sym(PySympy.Matrix(PyC.pylist([raw(e) for e in eqs])).jacobian(PyC.pylist([raw(v) for v in vars])))
    f = pylambdify(PyC.pylist([raw(v) for v in vars]), raw(J), "numpy")   # a function returning a numpy array
    w -> Matrix{Float64}(PyC.PyArray(f(w...)))
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
    "x^3 e^(2x)" => () -> S.integrate(x^3 * exp(2x), x),
    "1/(x^3+1)" => () -> S.integrate(1 / (x^3 + 1), x),
    "sec^3 x" => () -> S.integrate(sec(x)^3, x),
    "x/(x^4+1)" => () -> S.integrate(x / (x^4 + 1), x),
    "ln(x)^2/x^2" => () -> S.integrate(log(x)^2 / x^2, x),
    "e^x sin x" => () -> S.integrate(exp(x) * sin(x), x),
    "sqrt(1-x^2)" => () -> S.integrate(sqrt(1 - x^2), x),
    "1/(x sqrt(x^2-1))" => () -> S.integrate(1 / (x * sqrt(x^2 - 1)), x),
    "x asin x" => () -> S.integrate(x * asin(x), x),
    "1/(2+cos x)" => () -> S.integrate(1 / (2 + cos(x)), x),
    # definite integrals
    "Dalzell's integral" => () -> S.integrate(x^4 * (1 - x)^4 / (1 + x^2), (x, 0, 1)),
    "Dirichlet's integral" => () -> S.integrate(sin(x) / x, (x, 0, oo)),
    "The Gaussian integral" => () -> S.integrate(exp(-x^2), (x, 0, oo)),
    "A logarithm over 1-x" => () -> S.integrate(log(x) / (1 - x), (x, 0, 1)),
    "A power of the sine" => () -> S.integrate(sin(x)^4, (x, 0, PI)),
    "Planck's integral" => () -> S.integrate(x^3 / (exp(x) - 1), (x, 0, oo)),
    "x ln(1+x) on [0,1]" => () -> S.integrate(x * log(1 + x), (x, 0, 1)),
    "A quartic denominator on the line" => () -> S.integrate(1 / (x^4 + 1), (x, -oo, oo)),
    "A damped sine" => () -> S.integrate(x * exp(-x) * sin(x), (x, 0, oo)),
    # series and products
    "zeta(6)" => () -> S.summation(1 / n^6, (n, 1, oo)),
    "n^3/3^n" => () -> S.summation(n^3 / Sym(3)^n, (n, 1, oo)),
    "The alternating harmonic series" => () -> S.summation((-1)^(n + 1) / n, (n, 1, oo)),
    "A telescoping sum" => () -> S.summation(1 / (n * (n + 1) * (n + 2)), (n, 1, oo)),
    "Leibniz's series" => () -> S.summation((-1)^n / (2n + 1), (n, 0, oo)),
    "The binomial theorem at 2" => () -> S.summation(S.binomial(n, k) * Sym(2)^k, (k, 0, n)),
    "Nicomachus's theorem" => () -> S.summation(k^3, (k, 1, n)),
    "1/(4n^2-1)" => () -> S.summation(1 / (4n^2 - 1), (n, 1, oo)),
    "A product equal to 2" => () -> S.product((n + 1)^2 / (n * (n + 2)), (n, 1, oo)),
    # limits
    "(e^x-1-x)/x^2" => () -> S.limit((exp(x) - 1 - x) / x^2, x, 0),
    "(1-cos x)/x^2" => () -> S.limit((1 - cos(x)) / x^2, x, 0),
    "(1+2/x)^x" => () -> S.limit((1 + 2 / x)^x, x, oo),
    "x^x at 0" => () -> S.limit(x^x, x, 0, "+"),
    "(sin x - x)/x^3" => () -> S.limit((sin(x) - x) / x^3, x, 0),
    "n(2^(1/n)-1)" => () -> S.limit(n * (Sym(2)^(1 / n) - 1), n, oo),
    "sqrt(x^2+x)-x" => () -> S.limit(sqrt(x^2 + x) - x, x, oo),
    "(tan x - x)/x^3" => () -> S.limit((tan(x) - x) / x^3, x, 0),
    "1/x - 1/(e^x-1)" => () -> S.limit(1 / x - 1 / (exp(x) - 1), x, 0),
    # equations and inequalities
    "A cubic with integer roots" => () -> [cnum(r) for r in S.solve(x^3 - 6x^2 + 11x - 6, x)],
    "Sum and product" => () -> solution_tuples(S.solve([x + y - 5, x * y - 6], [x, y])),
    "A biquadratic" => () -> [cnum(r) for r in S.solve(x^4 - 10x^2 + 1, x)],
    "An exponential equation" => () -> [cnum(r) for r in S.solve(Sym(2)^x - Sym(3)^(x - 1), x)],
    "A circle and a line" => () -> solution_tuples(S.solve([x^2 + y^2 - 25, x - y - 1], [x, y])),
    "A cubic with one real root" => () -> [cnum(r) for r in S.solve(x^3 + x - 1, x)],
    "A quadratic inequality" => () -> S.solve(S.Lt(x^2 - 3x + 2, 0), x),
    "An absolute value inequality" => () -> S.solve(S.Lt(abs(2x - 3), 5), x),
    # polynomials
    "x^8-1 over Q" => () -> FACTOR(x^8 - 1),
    "Sophie Germain's identity" => () -> FACTOR(x^4 + 4),
    "x^3+y^3+z^3-3xyz" => () -> FACTOR(x^3 + y^3 + z^3 - 3x * y * z),
    "A polynomial gcd" => () -> S.gcd(x^4 - 1, x^6 - 1),
    "A resultant" => () -> S.resultant(x^2 + y^2 - 1, x - y, y),
    "A discriminant" => () -> S.discriminant(x^3 + p * x + q, x),
    "A partial fraction decomposition" => () -> S.apart(1 / ((x - 1) * (x + 2)^2), x),
    "Two conics" => () -> solution_tuples(S.solve([x^2 + y^2 - 1, x * y - Sym(1) / 4], [x, y])),
    # simplification
    "A nested radical" => () -> S.simplify(sqrt(7 + 4sqrt(Sym(3))) - 2 - sqrt(Sym(3))),
    "The Pythagorean identity" => () -> S.simplify(sin(x)^2 + cos(x)^2 - 1),
    "A removable singularity" => () -> S.simplify((x^3 - 1) / (x - 1) - x^2 - x - 1),
    "The golden cosine" => () -> S.simplify(cos(PI / 5) - (1 + sqrt(Sym(5))) / 4),
    "tan(pi/12)" => () -> S.simplify(tan(PI / 12) - 2 + sqrt(Sym(3))),
    "A minimal polynomial of degree six" => () -> S.minimal_polynomial(sqrt(Sym(2)) + Sym(3)^(Sym(1) / 3), x),
    "An exponential of a logarithm" => () -> (xp = S.Symbol("x"; positive = true); subs(S.simplify(exp(2log(xp)) - xp^2), xp => x)),
    "Zero identity: nested square root" => () -> S.simplify(sqrt(3 + 2sqrt(Sym(2))) - 1 - sqrt(Sym(2))),
    "Zero identity: nested cube root" => () -> S.simplify((7 + 5sqrt(Sym(2)))^(Sym(1) / 3) - 1 - sqrt(Sym(2))),
    "Zero identity: logarithms on positive reals" => () -> S.simplify(log(Sym(2)) + log(Sym(3)) - log(Sym(6))),
    "Zero identity: exponential of a logarithm" => () -> S.simplify(exp(log(Sym(2))) - 2),
    "Zero identity: sine at pi over six" => () -> S.simplify(sin(PI / 6) - half),
    "Nonzero control: rational residual" => () -> S.simplify(sqrt(Sym(2))^2 - 2 + 1 / pyint(big(10)^30)),
    "Nonzero control: near integer" => () -> S.simplify(exp(PI * sqrt(Sym(163))) - pyint(262537412640768744)),
    # differential equations
    "A harmonic oscillator" => () -> ode(S.Eq(yf(x).diff(x, 2) + 4yf(x), 0), [y1 -> y1.diff(x, 2) + 4y1]),
    "A forced linear equation" => () -> ode(S.Eq(yf(x).diff(x, 2) - 3yf(x).diff(x) + 2yf(x), exp(3x)),
                                           [y1 -> y1.diff(x, 2) - 3y1.diff(x) + 2y1 - exp(3x)]),
    "A first-order linear equation" => () -> ode(S.Eq(yf(x).diff(x) + 2x * yf(x), x), [y1 -> y1.diff(x) + 2x * y1 - x]),
    "A first-order Euler equation" => () -> ode(S.Eq(x * yf(x).diff(x) - yf(x), x^2), [y1 -> x * y1.diff(x) - y1 - x^2]),
    "A polynomial forcing" => () -> ode(S.Eq(yf(x).diff(x, 2) + yf(x), x), [y1 -> y1.diff(x, 2) + y1 - x]),
    "A separable equation" => () -> ode(S.Eq(yf(x).diff(x), yf(x)^2), [y1 -> y1.diff(x) - y1^2]),
    "An initial-value problem" => () -> ode(S.Eq(yf(x).diff(x, 2) + yf(x).diff(x) - 2yf(x), 0),
        [y1 -> y1.diff(x, 2) + y1.diff(x) - 2y1, y1 -> subs(y1, x => 0) - 1, y1 -> subs(y1.diff(x), x => 0)];
        ics = Dict(yf(0) => 1, yf(x).diff(x).subs(x, 0) => 0)),
    "A repeated characteristic root" => () -> ode(S.Eq(yf(x).diff(x, 2) - 2yf(x).diff(x) + yf(x), 0), [y1 -> y1.diff(x, 2) - 2y1.diff(x) + y1]),
    # linear algebra
    "A tridiagonal determinant" => () -> smat([2 1 0; 1 2 1; 0 1 2]).det(),
    "A 2x2 inverse" => () -> jmat(smat([4 7; 2 6]).inv()),
    "Eigenvalues of a symmetric matrix" => () -> (ev = smat([2 1; 1 2]).eigenvals(); vcat([fill(fnum(kk), Int(N(m))) for (kk, m) in ev]...)),
    "The rank of a singular matrix" => () -> smat([1 2 3; 4 5 6; 7 8 9]).rank(),
    "A linear system" => () -> [fnum(e) for e in vec(smat([2 1 -1; -3 -1 2; -2 1 2]).LUsolve(smat(reshape([8, -11, -3], 3, 1))))],
    "A characteristic polynomial" => () -> smat([1 2; 3 4]).charpoly(x).as_expr(),
    "A Fibonacci matrix power" => () -> jmat(smat([1 1; 1 0])^10),
    "A symbolic determinant" => () -> smat([a b; b a]).det(),
    # number theory
    "The Fermat number F6" => () -> sort([parse(BigInt, string(pp)) for pp in S.primefactors(pyint(big(2)^64 + 1))]),
    "A Mersenne prime of 89 bits" => () -> S.isprime(pyint(big(2)^89 - 1)),
    "A gcd of Mersenne numbers" => () -> S.gcd(pyint(big(2)^60 - 1), pyint(big(2)^84 - 1)),
    "A modular inverse" => () -> S.mod_inverse(17, 3120),
    "Euler's totient of a million" => () -> S.totient(10^6),
    "The next prime after 10^12" => () -> S.nextprime(10^12),
    "The Chinese remainder theorem" => () -> first(collect(PyC.pyimport("sympy.ntheory.modular").crt(PyC.pylist([3, 5, 7]), PyC.pylist([2, 3, 2])))),
    "A sum of divisors" => () -> S.divisor_sigma(360),
    # transforms and series expansions
    "A Laplace transform" => () -> LAPLACE(t * exp(-2t), t, s),
    "An inverse Laplace transform" => () -> ILAPLACE(1 / (s^2 + 4), s, t),
    "The Laplace transform of a cosine" => () -> LAPLACE(cos(2t), t, s),
    "Gamma at one half" => () -> S.gamma(half),
    "A Beta value" => () -> S.simplify(S.beta(2, 3)),
    "Gamma at five halves" => () -> S.gamma(Sym(5) / 2),
    "The series of tan" => () -> S.series(tan(x), x, 0, 8).removeO(),
    "The series of e^x sin x" => () -> S.series(exp(x) * sin(x), x, 0, 6).removeO(),
    # model to Jacobian
    "Jacobian: Brusselator N=10 (build)" => () -> jacobian_fn(10),
    "Jacobian: Brusselator N=50 (build)" => () -> jacobian_fn(50),
    "Jacobian: Brusselator N=10 (evaluate 1000 points)" => () -> jacobian_eval(10),
    "Jacobian: Brusselator N=50 (evaluate 1000 points)" => () -> jacobian_eval(50),
)
