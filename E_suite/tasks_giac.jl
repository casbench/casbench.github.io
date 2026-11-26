# Bench E tasks for Giac.jl as released upstream (no Julia-side layer of the
# fork). Tasks are written as a user would write them: giac_eval on an Xcas
# expression (the string path, bench A), to_julia for numeric answers, and
# the Symbolics bridge for the compiled Jacobians. Each task starts by
# clearing Giac's user variables (restart), so that no assignment leaks
# from one problem to the next. A task returns the answer, or (answer, post)
# with post() an auxiliary computation for the check outside the timed call.
using Symbolics   # the documented route to a compiled function: to_symbolics + build_function

ge(s) = geval(s)
tj(e) = e isa GiacExpr ? to_julia(e) : e
num(s) = tj(tj(ge("evalf(" * s * ")")))
# a Giac list of lists to a Julia matrix of Float64/ComplexF64
function matrix(s)
    m = tj(ge("evalf(" * s * ")"))
    m isa AbstractMatrix && return m
    m isa AbstractVector || error("not a matrix: " * s)
    rows = [tj.(tj(r)) for r in m]
    reduce(vcat, [permutedims(collect(r)) for r in rows])
end
# a Giac list of solution lists to tuples of numbers (complex kept)
function tuples(s)
    v = tj(ge("evalf(" * s * ")"))
    v isa AbstractVector || return v
    [Tuple(tj.(tj(w))) for w in v]
end
floats(s) = (v = tj(ge("evalf(" * s * ")")); v isa AbstractVector ? [tj(e) for e in v] : [v])
for i in 1:6
    VAR[Symbol("c$i")] = ge("c$i")
end
reset!() = (ge("restart"); giac_one_thread())   # one Giac thread, whatever restart resets

# an ODE: desolve, then the residual with the arbitrary constants set to 1; `template`
# is the residual with the unknown written as Y (substituted textually, since Giac
# evaluates diff(y,x) of a free symbol y to 0)
function ode(eq, var, fn, templates::Vector{String})
    sol = ge("desolve(" * eq * "," * var * "," * fn * ")")
    s = string(sol)
    s == "[]" && return sol
    if startswith(s, "[")
        v = elements(sol)          # several branches: the first one is checked
        isempty(v) || (sol = v[1])
    end
    post = () -> begin
        y = "(" * replace(string(sol), r"c_\d+" => "1") * ")"
        [ge("simplify(" * replace(tpl, "Y" => y) * ")") for tpl in templates]
    end
    (sol, post)
end

const TASKS = Dict{String,Any}()
task!(name, f) = (TASKS[name] = () -> (reset!(); f()))

# ---- 1 indefinite integrals
task!("sqrt(tan x)", () -> ge("integrate(sqrt(tan(x)),x)"))
task!("Chebyshev's pseudo-elliptic integral", () -> ge("integrate(x/sqrt(x^4+10*x^2-96*x-71),x)"))
task!("An arctangent of a radical", () -> ge("integrate((x^2-1)/((x^2+1)*sqrt(x^4+1)),x)"))
task!("A quintic denominator", () -> ge("integrate(1/(x^5-x+1),x)"))
task!("A fourth root", () -> ge("integrate(1/(1+x^4)^(1/4),x)"))
task!("Parts, twice", () -> ge("integrate(x^2*asin(x)^2,x)"))
task!("Exponential and logarithm (Risch)", () -> ge("integrate(exp(x)*(1+x*ln(x))/x,x)"))
task!("A Bessel function, to Struve functions", () -> ge("integrate(x^2*BesselJ(0,x),x)"))
task!("The error function squared", () -> ge("integrate(erf(x)^2,x)"))
# ---- 2 definite integrals
task!("Bose-Einstein type", () -> ge("integrate(x/(exp(x)-1),x,0,+infinity)"))
task!("Serret's integral", () -> ge("integrate(ln(1+x)/(1+x^2),x,0,1)"))
task!("A symmetry trick", () -> ge("integrate(x*sin(x)/(1+cos(x)^2),x,0,pi)"))
task!("Log-sine", () -> ge("integrate(ln(sin(x)),x,0,pi/2)"))
task!("Ahmed's integral", () -> ge("integrate(atan(sqrt(x^2+2))/((x^2+1)*sqrt(x^2+2)),x,0,1)"))
task!("Laplace's integral", () -> ge("integrate(cos(x)/(1+x^2),x,0,+infinity)"))
task!("A dilogarithm value", () -> ge("integrate(ln(x)*ln(1-x),x,0,1)"))
task!("Euler's constant", () -> ge("integrate(exp(-x)*ln(x)^2,x,0,+infinity)"))
task!("A Gaussian with a cosine", () -> ge("integrate(exp(-x^2)*cos(2*x),x,-infinity,+infinity)"))
task!("Frullani's integral", () -> ge("integrate((exp(-x)-exp(-2*x))/x,x,0,+infinity)"))
task!("The error function", () -> ge("integrate(erfc(x)^2,x,0,+infinity)"))
task!("A Bessel function on the half-line", () -> ge("integrate(BesselJ(0,x),x,0,+infinity)"))
task!("A damped Bessel function", () -> ge("integrate(exp(-x)*BesselJ(0,x),x,0,+infinity)"))
task!("A pendulum's period", () -> (ge("assume(a>0 and a<pi)"); r = ge("integrate(1/sqrt(cos(x)-cos(a)),x,0,a)"); r))
# ---- 3 sums and products
task!("zeta(4)", () -> ge("sum(1/n^4,n,1,+infinity)"))
task!("Harmonic numbers", () -> ge("sum(sum(1/k,k,1,n)/n^2,n,1,+infinity)"))
task!("Dirichlet beta(3)", () -> ge("sum((-1)^n/(2*n+1)^3,n,0,+infinity)"))
task!("Arithmetic-geometric", () -> ge("sum(n^2/2^n,n,1,+infinity)"))
task!("A central binomial series", () -> ge("sum(1/(n^2*comb(2*n,n)),n,1,+infinity)"))
task!("Vandermonde's identity", () -> ge("sum(comb(n,k)^2,k,0,n)"))
task!("A closed form in n", () -> ge("sum(k*2^k,k,1,n)"))
task!("A polylogarithm value", () -> ge("subst(sum(x^n/n^2,n,1,+infinity),x=1/2)"))
task!("A telescoping product", () -> ge("limit(product(1-1/n^2,n,2,N),N,+infinity)"))   # Giac has no infinite products: limit of the partial product
task!("Wallis's product", () -> ge("limit(product(4*n^2/(4*n^2-1),n,1,N),N,+infinity)"))
# ---- 4 limits
task!("tan sin - sin tan", () -> ge("limit((tan(sin(x))-sin(tan(x)))/x^7,x,0)"))
task!("Stirling", () -> ge("limit((n!)^(1/n)/n,n,+infinity)"))
task!("A second-order term of e", () -> ge("limit(x*((1+1/x)^x-exp(1)),x,+infinity)"))
task!("Nested exponentials (Gruntz)", () -> ge("limit(exp(x)*(exp(1/x-exp(-x))-exp(1/x)),x,+infinity)"))
task!("Cancelling poles", () -> ge("limit(1/x^2-1/sin(x)^2,x,0)"))
task!("A ratio of Gamma functions", () -> ge("limit(Gamma(x+1/2)/(Gamma(x)*sqrt(x)),x,+infinity)"))
task!("A power of sinc", () -> ge("limit((sin(x)/x)^(1/x^2),x,0)"))
task!("A bounded oscillation", () -> ge("limit((x+sin(x))/x,x,+infinity)"))
# ---- 5 equations and inequalities
task!("A sextic system", () -> tuples("cSolve([x^2+y^2=1,x^3=y],[x,y])"))
task!("A quintic solvable by radicals", () -> floats("cSolve(x^5-5*x+12=0,x)"))
task!("Every solution of cos x = 1/2", () -> (ge("all_trig_solutions:=1"); r = ge("solve(cos(x)=1/2,x)"); ge("all_trig_solutions:=0"); r))
task!("Lambert's W", () -> floats("solve(x*exp(x)=2,x)"))
task!("A symmetric system", () -> tuples("solve([x+y+z=6,x*y+y*z+z*x=11,x*y*z=6],[x,y,z])"))
task!("A quartic inequality", () -> ge("solve(x^4-5*x^2+4<0,x)"))
task!("Absolute values", () -> ge("solve(abs(x-1)+abs(x+2)<5,x)"))
# quantifier elimination: Giac has none; the discriminant route a user would take
task!("Quantifier elimination", () -> ge("solve(discriminant(x^2+b*x+1,x)<0,b)"))
# ---- 6 polynomial algebra
task!("Cyclotomic factors", () -> FACTOR(ge("x^105-1")))
task!("A symmetric septic", () -> FACTOR(ge("(x+y+z)^7-x^7-y^7-z^7")))
task!("Factoring over Q(sqrt 2)", () -> (L = tj(ge("factors(x^4+1,sqrt(2))")); (1, [(L[i], Int(tj(gx(L[i + 1])))) for i in 1:2:length(L)])))
# the number of complex solutions: the degree of the rational univariate representation
task!("The cyclic-6 system", () -> begin
    v = ["c$i" for i in 1:6]
    polys = String[]
    for m in 1:5
        push!(polys, join(["(" * join([v[mod1(k + j, 6)] for j in 0:m-1], "*") * ")" for k in 1:6], "+"))
    end
    push!(polys, join(v, "*") * "-1")
    ge("R:=gbasis([" * join(polys, ",") * "],[" * join(v, ",") * "],rur)")
    tj(ge("degree(R[2],lvar(R[2])[0])"))
end)
task!("Implicitization", () -> ge("resultant(x-t^2+1,y-t^3+t,t)"))
TASKS["Polynomial decomposition"] = missing     # no polynomial decomposition in Giac
# ---- 7 simplification and algebraic numbers
task!("Denesting", () -> ge("simplify(sqrt(5+2*sqrt(6))-sqrt(2)-sqrt(3))"))
task!("Ramanujan's denesting", () -> ge("simplify((2^(1/3)-1)^(1/3)-(1/9)^(1/3)+(2/9)^(1/3)-(4/9)^(1/3))"))
# the exact value of an algebraic number through its minimal polynomial
task!("A heptagon sum", () -> ge("simplify(cos(2*pi/7)+cos(4*pi/7)+cos(6*pi/7)+1/2)"))
task!("A minimal polynomial", () -> ge("pmin(sqrt(2)+sqrt(3)+sqrt(5),x)"))
task!("A trigonometric identity", () -> ge("simplify(sin(3*x)/sin(x)-cos(3*x)/cos(x)-2)"))
TASKS["Gauss's 17-gon"] = missing                # no expression of cos(2pi/17) in radicals in Giac
task!("An inverse cosine, with assumptions", () -> (ge("assume(x>pi and x<2*pi)"); r = ge("simplify(acos(cos(x))-(2*pi-x))"); ge("purge(x)"); r))
# ---- 8 differential equations
task!("Airy", () -> ode("y''=x*y", "x", "y", ["diff(Y,x,2)-x*Y"]))
task!("Bessel, order 1/2", () -> ode("x^2*y''+x*y'+(x^2-1/4)*y=0", "x", "y", ["x^2*diff(Y,x,2)+x*diff(Y,x)+(x^2-1/4)*Y"]))
task!("Riccati", () -> ode("y'=x^2+y^2", "x", "y", ["diff(Y,x)-x^2-Y^2"]))
task!("A nonlinear autonomous equation", () -> ode("y*y''=y'^2", "x", "y", ["Y*diff(Y,x,2)-diff(Y,x)^2"]))
task!("A forced Euler-Cauchy equation", () -> ode("x^2*y''-3*x*y'+4*y=x^2*ln(x)", "x", "y", ["x^2*diff(Y,x,2)-3*x*diff(Y,x)+4*Y-x^2*ln(x)"]))
task!("Bernoulli", () -> ode("y'+y=x*y^3", "x", "y", ["diff(Y,x)+Y-x*Y^3"]))
task!("An exponential solution (Kovacic)", () -> ode("y''=(x^2+1)*y", "x", "y", ["diff(Y,x,2)-(x^2+1)*Y"]))
task!("A forced initial-value problem", () -> ode("[y''-(x^2+1)*y=x*exp(-x^2/2),y(0)=0,y'(0)=1]", "x", "y",
      ["diff(Y,x,2)-(x^2+1)*Y-x*exp(-x^2/2)", "subst(Y,x=0)", "subst(diff(Y,x),x=0)-1"]))
task!("A Riccati equation with Airy solutions", () -> ode("y'=x+y^2", "x", "y", ["diff(Y,x)-x-Y^2"]))
task!("A pendulum released from rest", () -> ode("[y''+sin(y)=0,y(0)=a,y'(0)=0]", "x", "y", ["diff(Y,x,2)+sin(Y)", "subst(Y,x=0)-a", "subst(diff(Y,x),x=0)"]))
task!("Duffing's oscillator from rest", () -> ode("[y''+y+y^3=0,y(0)=a,y'(0)=0]", "x", "y", ["diff(Y,x,2)+Y+Y^3", "subst(Y,x=0)-a", "subst(diff(Y,x),x=0)"]))
# the linear system by the matrix exponential, as in the notebook
task!("A Jordan block", () -> floats("subst(exp(t*[[1,1,0],[0,1,1],[0,0,1]])*[1,1,1],t=7/10)"))
TASKS["The transport equation"] = missing       # no PDE solver in Giac
TASKS["The heat equation"] = missing             # no PDE solver in Giac
# ---- 9 linear algebra
task!("Symbolic eigenvalues", () -> floats("eigenvals(subst([[a,1,0],[1,a,1],[0,1,a]],a=13/10))"))
task!("A Jordan form", () -> (ge("PJ:=jordan([[5,4,2,1],[0,1,-1,-1],[-1,-1,3,0],[1,1,-1,2]])"); matrix("PJ[1]")))
task!("A matrix exponential", () -> matrix("subst(exp(t*[[0,1],[-1,0]]),t=7/10)"))
task!("A Vandermonde determinant", () -> FACTOR(ge("det([[1,a,a^2,a^3,a^4],[1,b,b^2,b^3,b^4],[1,x,x^2,x^3,x^4],[1,y,y^2,y^3,y^4],[1,z,z^2,z^3,z^4]])")))
task!("A Smith normal form", () -> (ge("UDV:=ismith([[2,4,4],[-6,6,12],[10,-4,-16]])"); matrix("UDV[1]")))
# ---- 10 number theory (PARI through Giac's `pari` command where Giac has no command)
task!("The Fermat number F7", () -> (L = tj(ge("ifactors(2^128+1)")); [big(L[1]), big(L[3])]))
task!("A Mersenne prime", () -> ge("isprime(2^521-1)"))
task!("A discrete logarithm", () -> big(tj(ge("pari(\"znlog\",123456789 mod 1000000007,5 mod 1000000007)"))))
task!("Pell's equation", () -> begin
    r = elements(ge("isolve(x^2-61*y^2=1)"))
    sx = replace(string(ge("rhs(" * string(r[1]) * ")")), r"_?[A-Za-z]_?\d+" => "1")
    sy = replace(string(ge("rhs(" * string(r[2]) * ")")), r"_?[A-Za-z]_?\d+" => "1")
    (big(tj(ge("simplify(" * sx * ")"))), big(tj(ge("simplify(" * sy * ")"))))
end)
task!("A periodic continued fraction", () -> ge("dfc(sqrt(61))"))
task!("Partitions", () -> big(tj(ge("pari(\"numbpart\",200)"))))
# ---- 11 transforms and special functions
task!("A Laplace transform", () -> ge("laplace(t^2*exp(-t)*sin(t),t,s)"))
task!("An inverse Laplace transform", () -> ge("ilaplace(1/(s^2+1)^2,s,t)"))
task!("A delayed step", () -> ge("ilaplace(exp(-s)/s,s,t)"))
task!("The series of Lambert's W", () -> ge("convert(series(LambertW(x),x,0,5),polynom)"))
TASKS["A hypergeometric function"] = missing     # no hypergeometric function in Giac
task!("Gamma's reflection formula", () -> ge("simplify(Gamma(1/4)*Gamma(3/4))"))
task!("The sine integral's Laplace transform", () -> ge("laplace(Si(t),t,s)"))
task!("An inverse Laplace transform to a Bessel function", () -> ge("ilaplace(1/sqrt(s^2+1),s,t)"))
TASKS["A polylogarithm value"] = missing         # no polylogarithm in Giac
# ---- 12 control
# Routh-Hurwitz conditions of s^3 + 3 s^2 + 3 s + (1 + k), written out, solved for k
task!("A stability region", () -> ge("solve((3*3-(1+k)>0) and (1+k>0),k)"))
# A'P + PA + I = 0 with P = [[p,q],[q,r]]: the three entries, solved
task!("A Lyapunov equation", () -> matrix("subst([[p,q],[q,r]],[p,q,r],solve([-4*q+1=0,p-3*q-2*r=0,2*q-6*r+1=0],[p,q,r])[0])"))
task!("A Riccati equation (LQR)", () -> begin
    sols = tuples("solve([-q^2+1=0,p-q*r=0,2*q-r^2+1=0],[p,q,r])")
    for (p, q, r) in sols
        (isreal(p) && isreal(q) && isreal(r)) || continue
        p, q, r = real(p), real(q), real(r)
        p > 0 && p * r - q^2 > 0 && return [p q; q r]
    end
    nothing
end)
task!("The unicycle's Lie algebra rank", () -> begin
    ge("f1:=[cos(th),sin(th),0]"); ge("f2:=[0,0,1]"); ge("X:=[px,py,th]")
    ge("br:=seq(sum(f1[j]*diff(f2[i],X[j])-f2[j]*diff(f1[i],X[j]),j,0,2),i,0,2)")
    # the rank of the symbolic matrix is taken at th = 3/10 (Giac's rank refuses symbolic entries)
    tj(ge("rank(subst([f1,f2,br],th=3/10))"))
end)
task!("A center manifold", () -> begin
    ge("h:=c2*x^2+c3*x^3+c4*x^4"); ge("R:=expand(diff(h,x)*x*h+h+x^2)")
    ge("subst(h,[c2,c3,c4],solve([coeff(R,x,2)=0,coeff(R,x,3)=0,coeff(R,x,4)=0],[c2,c3,c4])[0])")
end)
TASKS["A sum-of-squares certificate"] = missing  # no positivity proof in Giac
TASKS["Motzkin's polynomial"] = missing          # no positivity proof in Giac
# ---- 13 model to Jacobian: the Jacobian by diff, compiled through the Symbolics bridge
function bruss(N)
    eqs = String[]; vars = String[]
    for i in 1:N
        ip, im = mod1(i + 1, N), mod1(i - 1, N)
        push!(eqs, "1+u$i^2*v$i-4*u$i+(u$ip-2*u$i+u$im)"); push!(eqs, "3*u$i-u$i^2*v$i+(v$ip-2*v$i+v$im)")
        push!(vars, "u$i"); push!(vars, "v$i")
    end
    eqs, vars
end
function jacobian_fn(N)
    eqs, vars = bruss(N)
    # Giac's diff of a vector by a vector is indexed (variable, function): transposed
    J = ge("tran(diff([" * join(eqs, ",") * "],[" * join(vars, ",") * "]))")
    Js = to_symbolics(J)
    Js isa AbstractMatrix || (Js = reduce(vcat, [permutedims(collect(r)) for r in Js]))   # rows to a Matrix{Num}
    svars = [to_symbolics(ge(v)) for v in vars]
    f = Symbolics.build_function(Js, svars; expression = Val(false))[1]
    w -> f(w)
end
task!("Jacobian: Brusselator N=10 (build)", () -> jacobian_fn(10))
task!("Jacobian: Brusselator N=50 (build)", () -> jacobian_fn(50))
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
task!("Jacobian: Brusselator N=10 (evaluate 1000 points)", () -> jacobian_eval(10))
task!("Jacobian: Brusselator N=50 (evaluate 1000 points)", () -> jacobian_eval(50))

# the family of solutions of cos x = 1/2: each listed solution with the parameter set to kk
function EVALFAMILY(out, params, kk)
    vals = Any[]
    for e in elements(out)
        s = string(e)
        for pname in params
            s = replace(s, Regex("\\b" * pname * "\\b") => "(" * string(kk) * ")")
        end
        push!(vals, tonum(tj(ge("evalf(" * s * ")"))))
    end
    vals
end

# Fixed identity differences and near-identity controls; case names are shared
# by the other adapters and the reference intervals live in zero_reference.jl.
for (name, expression) in (
    "Zero identity: nested square root" => "sqrt(3+2*sqrt(2))-1-sqrt(2)",
    "Zero identity: nested cube root" => "(7+5*sqrt(2))^(1/3)-1-sqrt(2)",
    "Zero identity: logarithms on positive reals" => "ln(2)+ln(3)-ln(6)",
    "Zero identity: exponential of a logarithm" => "exp(ln(2))-2",
    "Zero identity: sine at pi over six" => "sin(pi/6)-1/2",
    "Nonzero control: rational residual" => "sqrt(2)^2-2+1/10^30",
    "Nonzero control: near integer" => "exp(pi*sqrt(163))-262537412640768744",
)
    task!(name, () -> ge("simplify(" * expression * ")"))
end
