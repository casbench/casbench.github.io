# Bench E tasks for SymPy through SymPyPythonCall.jl, as a SymPy user would
# write them.
const th, px, py = S.symbols("th px py")  # p, q and r are already defined by the adapter
const C6 = collect(S.symbols("c1:7"))
for i in 1:6
    VAR[Symbol("c$i")] = C6[i]
end
const Cc1, Cc2, Cc3 = S.symbols("C1 C2 C3")
half = Sym(1) / 2
fl(e) = Float64(real(N(e)))
cx(e) = ComplexF64(N(e))
tup(tt) = Tuple(cx(e) for e in collect(tt))
# a SymPy Matrix from a Julia matrix (rows, cols, flat row-major list: PythonCall would
# otherwise flatten a vector of vectors into a column)
smat(M::AbstractMatrix) = S.Matrix(size(M, 1), size(M, 2), vec(permutedims(M)))
scol(v::AbstractVector) = S.Matrix(length(v), 1, v)
function jmat(M)
    M isa AbstractMatrix && return [fl(e) for e in M]
    rows, cols = Int(N(M.rows)), Int(N(M.cols))
    [fl(M[i, j]) for i in 1:rows, j in 1:cols]
end
bigint(e) = parse(BigInt, replace(string(e), " " => ""))
const PyC = SymPyPythonCall.PythonCall
const PySympy = PyC.pyimport("sympy")
raw(e) = e isa Sym ? getfield(e, :o) : e               # the Python object behind a Sym
# SymPyPythonCall converts SymPy matrices to Julia matrices of Sym; a Python-side Matrix is
# rebuilt when a Python function (lambdify, smith_normal_form) must receive one
pymat(M::AbstractMatrix) = PySympy.Matrix(PyC.pylist([PyC.pylist([raw(e) for e in M[i, :]]) for i in 1:size(M, 1)]))
const yf = S.Function("y")
d_sym(f, v, n = 1) = S.diff(f, v, n)
# an ODE: dsolve, then the residuals with the constants set to 1
function ode(eq, residuals::Vector; var = x, ics = nothing)
    sol = ics === nothing ? S.dsolve(eq, yf(var)) : S.dsolve(eq, yf(var); ics = ics)
    startswith(string(sol), "[") && (sol = first(collect(sol)))   # several branches: the first one is checked
    rhs = sol.rhs
    post = () -> begin
        y1 = rhs.subs(Dict(Cc1 => 1, Cc2 => 1, Cc3 => 1))
        [S.simplify(res(y1).doit()) for res in residuals]
    end
    (rhs, post)
end
cyclic6() = begin
    v = C6
    polys = Any[]
    for m in 1:5
        push!(polys, sum(prod(v[mod1(k + j, 6)] for j in 0:m-1) for k in 1:6))
    end
    push!(polys, prod(v) - 1)
    polys
end
function bruss(N)
    U = collect(S.symbols("u1:$(N+1)")); V = collect(S.symbols("v1:$(N+1)"))
    eqs = Any[]; vars = Any[]
    for i in 1:N
        ip, im = mod1(i + 1, N), mod1(i - 1, N)
        push!(eqs, 1 + U[i]^2 * V[i] - 4U[i] + (U[ip] - 2U[i] + U[im])); push!(eqs, 3U[i] - U[i]^2 * V[i] + (V[ip] - 2V[i] + V[im]))
        push!(vars, U[i]); push!(vars, V[i])
    end
    eqs, vars
end
function jacobian_fn(N)
    eqs, vars = bruss(N)
    J = scol(eqs).jacobian(vars)
    f = PySympy.lambdify(PyC.pylist(raw.(vars)), pymat(J), "numpy")   # a Python function returning a numpy array
    w -> PyC.pyconvert(Matrix{Float64}, f(w...))
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
    "sqrt(tan x)" => () -> integrate(sqrt(tan(x)), x),
    "Chebyshev's pseudo-elliptic integral" => () -> integrate(x / sqrt(x^4 + 10x^2 - 96x - 71), x),
    "An arctangent of a radical" => () -> integrate((x^2 - 1) / ((x^2 + 1) * sqrt(x^4 + 1)), x),
    "A quintic denominator" => () -> integrate(1 / (x^5 - x + 1), x),
    "A fourth root" => () -> integrate(1 / (1 + x^4)^(Sym(1) / 4), x),
    "Parts, twice" => () -> integrate(x^2 * asin(x)^2, x),
    "Exponential and logarithm (Risch)" => () -> integrate(exp(x) * (1 + x * log(x)) / x, x),
    "A Bessel function, to Struve functions" => () -> integrate(x^2 * S.besselj(0, x), x),
    "The error function squared" => () -> integrate(S.erf(x)^2, x),
    "Bose-Einstein type" => () -> integrate(x / (exp(x) - 1), (x, 0, oo)),
    "Serret's integral" => () -> integrate(log(1 + x) / (1 + x^2), (x, 0, 1)),
    "A symmetry trick" => () -> integrate(x * sin(x) / (1 + cos(x)^2), (x, 0, PI)),
    "Log-sine" => () -> integrate(log(sin(x)), (x, 0, PI / 2)),
    "Ahmed's integral" => () -> integrate(atan(sqrt(x^2 + 2)) / ((x^2 + 1) * sqrt(x^2 + 2)), (x, 0, 1)),
    "Laplace's integral" => () -> integrate(cos(x) / (1 + x^2), (x, 0, oo)),
    "A dilogarithm value" => () -> integrate(log(x) * log(1 - x), (x, 0, 1)),
    "Euler's constant" => () -> integrate(exp(-x) * log(x)^2, (x, 0, oo)),
    "A Gaussian with a cosine" => () -> integrate(exp(-x^2) * cos(2x), (x, -oo, oo)),
    "Frullani's integral" => () -> integrate((exp(-x) - exp(-2x)) / x, (x, 0, oo)),
    "The error function" => () -> integrate(S.erfc(x)^2, (x, 0, oo)),
    "A Bessel function on the half-line" => () -> integrate(S.besselj(0, x), (x, 0, oo)),
    "A damped Bessel function" => () -> integrate(exp(-x) * S.besselj(0, x), (x, 0, oo)),
    "A pendulum's period" => () -> (ap = S.symbols("a"; positive = true); integrate(1 / sqrt(cos(x) - cos(ap)), (x, 0, ap)).subs(ap, a)),
    "zeta(4)" => () -> S.summation(1 / n^4, (n, 1, oo)),
    "Harmonic numbers" => () -> S.summation(S.harmonic(n) / n^2, (n, 1, oo)),
    "Dirichlet beta(3)" => () -> S.summation((-1)^n / (2n + 1)^3, (n, 0, oo)),
    "Arithmetic-geometric" => () -> S.summation(n^2 / 2^n, (n, 1, oo)),
    "A central binomial series" => () -> S.summation(1 / (n^2 * S.binomial(2n, n)), (n, 1, oo)),
    "Vandermonde's identity" => () -> (ni = S.symbols("n", integer = true, positive = true); S.summation(S.binomial(ni, k)^2, (k, 0, ni)).subs(ni, n)),   # a plain n gives a Piecewise on re(n)
    "A closed form in n" => () -> S.summation(k * 2^k, (k, 1, n)),
    "A polylogarithm value" => () -> S.summation(x^n / n^2, (n, 1, oo)).subs(x, half),
    # SymPy leaves an infinite product unevaluated; as for Giac, the limit of the partial product is asked
    "A telescoping product" => () -> (NN = S.symbols("N", integer = true, positive = true); S.limit(S.product(1 - 1 / n^2, (n, 2, NN)), NN, oo)),
    "Wallis's product" => () -> (NN = S.symbols("N", integer = true, positive = true); S.limit(S.product(4n^2 / (4n^2 - 1), (n, 1, NN)), NN, oo)),
    "tan sin - sin tan" => () -> limit((tan(sin(x)) - sin(tan(x))) / x^7, x => 0),
    "Stirling" => () -> limit(S.factorial(n)^(1 / n) / n, n => oo),
    "A second-order term of e" => () -> limit(x * ((1 + 1 / x)^x - E), x => oo),
    "Nested exponentials (Gruntz)" => () -> limit(exp(x) * (exp(1 / x - exp(-x)) - exp(1 / x)), x => oo),
    "Cancelling poles" => () -> limit(1 / x^2 - 1 / sin(x)^2, x => 0),
    "A ratio of Gamma functions" => () -> limit(S.gamma(x + half) / (S.gamma(x) * sqrt(x)), x => oo),
    "A power of sinc" => () -> limit((sin(x) / x)^(1 / x^2), x => 0),
    "A bounded oscillation" => () -> limit((x + sin(x)) / x, x => oo),
    "A sextic system" => () -> [tup(s) for s in collect(solve([x^2 + y^2 - 1, x^3 - y], [x, y]))],
    "A quintic solvable by radicals" => () -> collect(solve(x^5 - 5x + 12, x)),
    "Every solution of cos x = 1/2" => () -> S.solveset(S.Eq(cos(x), half), x, S.Reals),
    "Lambert's W" => () -> collect(solve(x * exp(x) - 2, x)),
    "A symmetric system" => () -> [tup(s) for s in collect(solve([x + y + z - 6, x * y + y * z + z * x - 11, x * y * z - 6], [x, y, z]))],
    "A quartic inequality" => () -> S.solve_univariate_inequality(S.Lt(x^4 - 5x^2 + 4, 0), x),
    "Absolute values" => () -> S.reduce_inequalities(S.Lt(S.Abs(x - 1) + S.Abs(x + 2), 5), x),
    "Quantifier elimination" => () -> S.reduce_inequalities(S.Lt(S.discriminant(x^2 + b * x + 1, x), 0), b),   # no quantifier elimination in SymPy; the discriminant route
    "Cyclotomic factors" => () -> FACTOR(x^105 - 1),
    "A symmetric septic" => () -> FACTOR((x + y + z)^7 - x^7 - y^7 - z^7),
    "Factoring over Q(sqrt 2)" => () -> ((uu, fs) = S.factor_list(x^4 + 1; extension = sqrt(Sym(2))); (uu, [(g, toint(m)) for (g, m) in fs])),
    "The cyclic-6 system" => () -> length(collect(S.solve_poly_system(cyclic6(), C6...))),
    "Implicitization" => () -> S.resultant(x - t^2 + 1, y - t^3 + t, t),
    "Polynomial decomposition" => () -> (L = collect(S.decompose(x^6 + 6x^4 + x^3 + 9x^2 + 3x - 5)); (L[1], L[2])),
    "Denesting" => () -> (log_input!("simplify(sqrt(5 + 2*sqrt(6)) - sqrt(2) - sqrt(3))"); S.simplify(sqrt(5 + 2sqrt(Sym(6))) - sqrt(Sym(2)) - sqrt(Sym(3)))),
    "Ramanujan's denesting" => () -> (log_input!("simplify((2**Rational(1,3)-1)**Rational(1,3)-Rational(1,9)**Rational(1,3)+Rational(2,9)**Rational(1,3)-Rational(4,9)**Rational(1,3))"); S.simplify((Sym(2)^(Sym(1) / 3) - 1)^(Sym(1) / 3) - (Sym(1)/9)^(Sym(1)/3) + (Sym(2)/9)^(Sym(1)/3) - (Sym(4)/9)^(Sym(1)/3))),
    "A heptagon sum" => () -> (log_input!("simplify(cos(2*pi/7)+cos(4*pi/7)+cos(6*pi/7)+Rational(1,2))"); S.simplify(cos(2PI / 7) + cos(4PI / 7) + cos(6PI / 7) + Sym(1)/2)),
    "A minimal polynomial" => () -> S.minimal_polynomial(sqrt(Sym(2)) + sqrt(Sym(3)) + sqrt(Sym(5)), x),
    "A trigonometric identity" => () -> (log_input!("simplify(sin(3*x)/sin(x)-cos(3*x)/cos(x)-2)"); S.simplify(sin(3x) / sin(x) - cos(3x) / cos(x) - 2)),
    "Gauss's 17-gon" => () -> cos(2PI / 17).rewrite(sqrt),
    "An inverse cosine, with assumptions" => () -> (xp = S.symbols("x"; positive = true); log_input!("refine(acos(cos(x))-(2*pi-x), pi<x<2*pi)"); S.refine(S.acos(cos(xp)) - (2PI - xp), S.Q.gt(xp, PI) & S.Q.lt(xp, 2PI)).subs(xp, x)),
    "Airy" => () -> ode(S.Eq(d_sym(yf(x), x, 2), x * yf(x)), [y1 -> d_sym(y1, x, 2) - x * y1]),
    "Bessel, order 1/2" => () -> ode(S.Eq(x^2 * d_sym(yf(x), x, 2) + x * d_sym(yf(x), x) + (x^2 - Sym(1) / 4) * yf(x), 0), [y1 -> x^2 * d_sym(y1, x, 2) + x * d_sym(y1, x) + (x^2 - Sym(1) / 4) * y1]),
    "Riccati" => () -> ode(S.Eq(d_sym(yf(x), x), x^2 + yf(x)^2), [y1 -> d_sym(y1, x) - x^2 - y1^2]),
    "A nonlinear autonomous equation" => () -> ode(S.Eq(yf(x) * d_sym(yf(x), x, 2), d_sym(yf(x), x)^2), [y1 -> y1 * d_sym(y1, x, 2) - d_sym(y1, x)^2]),
    "A forced Euler-Cauchy equation" => () -> ode(S.Eq(x^2 * d_sym(yf(x), x, 2) - 3x * d_sym(yf(x), x) + 4yf(x), x^2 * log(x)), [y1 -> x^2 * d_sym(y1, x, 2) - 3x * d_sym(y1, x) + 4y1 - x^2 * log(x)]),
    "Bernoulli" => () -> ode(S.Eq(d_sym(yf(x), x) + yf(x), x * yf(x)^3), [y1 -> d_sym(y1, x) + y1 - x * y1^3]),
    "An exponential solution (Kovacic)" => () -> ode(S.Eq(d_sym(yf(x), x, 2), (x^2 + 1) * yf(x)), [y1 -> d_sym(y1, x, 2) - (x^2 + 1) * y1]),
    "A forced initial-value problem" => () -> ode(S.Eq(d_sym(yf(x), x, 2) - (x^2 + 1) * yf(x), x * exp(-x^2 / 2)),
        [y1 -> d_sym(y1, x, 2) - (x^2 + 1) * y1 - x * exp(-x^2 / 2), y1 -> y1.subs(x, 0), y1 -> d_sym(y1, x).subs(x, 0) - 1];
        ics = Dict(yf(0) => 0, d_sym(yf(x), x).subs(x, 0) => 1)),
    "A Riccati equation with Airy solutions" => () -> ode(S.Eq(d_sym(yf(x), x), x + yf(x)^2), [y1 -> d_sym(y1, x) - x - y1^2]),
    "A pendulum released from rest" => () -> ode(S.Eq(d_sym(yf(x), x, 2) + sin(yf(x)), 0), [y1 -> d_sym(y1, x, 2) + sin(y1), y1 -> y1.subs(x, 0) - a, y1 -> d_sym(y1, x).subs(x, 0)]; ics = Dict(yf(0) => a, d_sym(yf(x), x).subs(x, 0) => 0)),
    "Duffing's oscillator from rest" => () -> ode(S.Eq(d_sym(yf(x), x, 2) + yf(x) + yf(x)^3, 0), [y1 -> d_sym(y1, x, 2) + y1 + y1^3, y1 -> y1.subs(x, 0) - a, y1 -> d_sym(y1, x).subs(x, 0)]; ics = Dict(yf(0) => a, d_sym(yf(x), x).subs(x, 0) => 0)),
    "A Jordan block" => () -> vec([fl(e) for e in collect(((t * smat(Sym[1 1 0; 0 1 1; 0 0 1])).exp() * scol(Sym[1, 1, 1])).subs(t, Sym(7) / 10))]),
    "The transport equation" => () -> begin
        uf = S.Function("u")
        sol = S.pdsolve(S.Eq(d_sym(uf(x, y), x) + 2D(uf(x, y), y), 0), uf(x, y)).rhs
        # the arbitrary function chosen as F(w) = w^2, to evaluate the residual
        post = () -> begin
            Fs = S.Function("F")                      # pdsolve names the arbitrary function F
            w = S.symbols("w")
            s1 = sol.replace(Fs, S.Lambda(w, w^2))
            [S.simplify(d_sym(s1, x) + 2D(s1, y))]
        end
        (sol, post)
    end,
    "The heat equation" => missing,            # pdsolve takes no boundary conditions
    "Symbolic eigenvalues" => () -> [fl(e.subs(a, Sym(13) / 10)) for e in collect(keys(smat(Sym[a 1 0; 1 a 1; 0 1 a]).eigenvals()))],
    "A Jordan form" => () -> jmat(collect(smat(Sym[5 4 2 1; 0 1 -1 -1; -1 -1 3 0; 1 1 -1 2]).jordan_form())[2]),
    "A matrix exponential" => () -> jmat((t * smat(Sym[0 1; -1 0])).exp().subs(t, Sym(7) / 10)),
    "A Vandermonde determinant" => () -> FACTOR(smat(Sym[v^j for v in (a, b, x, y, z), j in 0:4]).det()),
    "A Smith normal form" => () -> jmat(Sym(PyC.pyimport("sympy.matrices.normalforms").smith_normal_form(pymat([2 4 4; -6 6 12; 10 -4 -16]); domain = PySympy.ZZ))),
    "The Fermat number F7" => () -> sort([bigint(kk) for kk in collect(keys(S.factorint(Sym(2)^128 + 1)))]),
    "A Mersenne prime" => () -> S.isprime(Sym(2)^521 - 1),
    "A discrete logarithm" => () -> bigint(S.discrete_log(1000000007, 123456789, 5)),
    "Pell's equation" => () -> (sol = first(collect(SymPyPythonCall.PythonCall.pyimport("sympy.solvers.diophantine.diophantine").diop_DN(61, 1))); (bigint(collect(sol)[1]), bigint(collect(sol)[2]))),
    "A periodic continued fraction" => () -> S.continued_fraction_periodic(0, 1, 61),
    "Partitions" => () -> bigint(S.npartitions(200)),
    "A Laplace transform" => () -> S.laplace_transform(t^2 * exp(-t) * sin(t), t, s; noconds = true),
    "An inverse Laplace transform" => () -> S.inverse_laplace_transform(1 / (s^2 + 1)^2, s, t),
    "A delayed step" => () -> S.inverse_laplace_transform(exp(-s) / s, s, t),
    "The series of Lambert's W" => () -> S.series(S.LambertW(x), x, 0, 6).removeO(),
    "A hypergeometric function" => () -> S.hyperexpand(S.hyper([1, 1], [2], x)),
    "Gamma's reflection formula" => () -> S.gammasimp(S.gamma(Sym(1) / 4) * S.gamma(Sym(3) / 4)),
    "The sine integral's Laplace transform" => () -> S.laplace_transform(S.Si(t), t, s; noconds = true),
    "An inverse Laplace transform to a Bessel function" => () -> S.inverse_laplace_transform(1 / sqrt(s^2 + 1), s, t),
    "A polylogarithm value" => () -> S.expand_func(S.polylog(3, half)),
    "A stability region" => () -> S.reduce_inequalities([S.Gt(3 * 3 - (1 + k), 0), S.Gt(1 + k, 0)], k),   # the Routh-Hurwitz conditions written out
    "A Lyapunov equation" => () -> (sol = first(collect(solve([-4q + 1, p - 3q - 2r, 2q - 6r + 1], [p, q, r]; dict = true))); jmat(smat(Sym[p q; q r]).subs(sol))),
    "A Riccati equation (LQR)" => () -> begin
        for sol in collect(solve([-q^2 + 1, p - q * r, 2q - r^2 + 1], [p, q, r]))
            pp, qq, rr = tup(sol)
            (isreal(pp) && isreal(qq) && isreal(rr)) || continue
            pp, qq, rr = real(pp), real(qq), real(rr)
            pp > 0 && pp * rr - qq^2 > 0 && return [pp qq; qq rr]
        end
        nothing
    end,
    "The unicycle's Lie algebra rank" => () -> begin
        f1 = scol(Sym[cos(th), sin(th), 0]); f2 = scol(Sym[0, 0, 1]); X = [px, py, th]
        br = f2.jacobian(X) * f1 - f1.jacobian(X) * f2
        Int(N(f1.row_join(f2).row_join(br).rank()))
    end,
    "A center manifold" => () -> begin
        c2, c3, c4 = S.symbols("c2 c3 c4")
        h = c2 * x^2 + c3 * x^3 + c4 * x^4
        rr = S.expand(d_sym(h, x) * x * h + h + x^2)
        h.subs(first(collect(solve([rr.coeff(x, 2), rr.coeff(x, 3), rr.coeff(x, 4)], [c2, c3, c4]; dict = true))))
    end,
    "A sum-of-squares certificate" => missing,  # no positivity proof in SymPy
    "Motzkin's polynomial" => missing,          # no positivity proof in SymPy
    "Jacobian: Brusselator N=10 (build)" => () -> jacobian_fn(10),
    "Jacobian: Brusselator N=50 (build)" => () -> jacobian_fn(50),
    "Jacobian: Brusselator N=10 (evaluate 1000 points)" => () -> jacobian_eval(10),
    "Jacobian: Brusselator N=50 (evaluate 1000 points)" => () -> jacobian_eval(50),
)

# the family of solutions of cos x = 1/2 (a union of image sets with an integer parameter):
# its elements in (-10, 10), the same list for every kk
function EVALFAMILY(out, params, kk)
    [fl(e) for e in collect(out.intersect(S.Interval(-10, 10)))]
end

for (name, expression) in (
    "Zero identity: nested square root" => "sqrt(3+2*sqrt(2))-1-sqrt(2)",
    "Zero identity: nested cube root" => "(7+5*sqrt(2))**(1/3)-1-sqrt(2)",
    "Zero identity: logarithms on positive reals" => "log(2)+log(3)-log(6)",
    "Zero identity: exponential of a logarithm" => "exp(log(2))-2",
    "Zero identity: sine at pi over six" => "sin(pi/6)-1/2",
    "Nonzero control: rational residual" => "sqrt(2)**2-2+1/10**30",
    "Nonzero control: near integer" => "exp(pi*sqrt(163))-262537412640768744",
)
    TASKS[name] = () -> begin
        log_input!("sympify(" * repr(expression) * ", evaluate=False)")
        ex = S.sympify(expression; evaluate = false)
        log_input!("simplify(" * string(ex) * ")")
        S.simplify(ex)
    end
end
