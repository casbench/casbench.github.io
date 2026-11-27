# Bench E tasks for Giac.jl, written for this repository: each task sends the Xcas
# command a Giac user would type (giac_eval, the string path of bench A) and
# converts the answer with to_julia where the check needs plain numbers. Every
# task starts from a clean Giac session (restart, then one Giac thread), so that
# no assignment or assumption leaks from one problem to the next. A task returns
# the answer, or (answer, post) with post() a residual computed outside the timed
# call.
using Symbolics   # the compiled Jacobians go through Giac.jl's Symbolics bridge

ge(s) = geval(s)
tj(e) = e isa GiacExpr ? to_julia(e) : e
reset!() = (giac_eval("restart"); giac_one_thread())
task(f) = () -> (reset!(); f())

# the elements of a Giac list, as Julia values
items(e) = (v = tj(e); v isa AbstractVector ? collect(v) : [v])
# numbers from a Giac answer: every element through evalf (complex values kept)
numbers(s) = [ComplexF64(tj(w)) for w in items(ge("evalf(" * s * ")"))]
# the solutions of a system, [[x, y], ...] in Giac, as tuples of numbers
solution_tuples(s) = [Tuple(ComplexF64(tj(c)) for c in items(w)) for w in items(ge("evalf(" * s * ")"))]
# a Giac matrix as a Julia matrix of Float64
function jmatrix(s)
    rows = items(ge("evalf(" * s * ")"))
    reduce(vcat, [permutedims(Float64.(real.(tj.(items(r))))) for r in rows])
end

# an ODE: desolve, then the residuals with Y replaced by the solution with every constant c_k set to 1
function ode(eq, residuals::Vector{String})
    sol = ge("desolve(" * eq * ",y)")
    s = string(sol)
    s == "[]" && return sol
    first_sol = startswith(s, "[") ? string(ge("(" * s * ")[0]")) : s
    post = () -> begin
        y1 = string(ge("subst(" * first_sol * ",[c_0=1,c_1=1,c_2=1])"))
        [ge("simplify(" * replace(r, "Y" => "(" * y1 * ")") * ")") for r in residuals]
    end
    (sol, post)
end

# the Brusselator on a ring of N cells, as Giac expressions, its Jacobian computed by Giac and compiled through
# to_symbolics and Symbolics.build_function (state order u1, v1, ..., uN, vN)
function jacobian_fn(N)
    us = ["u$i" for i in 1:N]; vs = ["v$i" for i in 1:N]
    eqs = String[]
    for i in 1:N
        ip, im = mod1(i + 1, N), mod1(i - 1, N)
        push!(eqs, "1+$(us[i])^2*$(vs[i])-4*$(us[i])+($(us[ip])-2*$(us[i])+$(us[im]))")
        push!(eqs, "3*$(us[i])-$(us[i])^2*$(vs[i])+($(vs[ip])-2*$(vs[i])+$(vs[im]))")
    end
    vars = vec(permutedims(hcat(us, vs)))
    J = ge("tran(diff([" * join(eqs, ",") * "],[" * join(vars, ",") * "]))")   # diff of a list by a list: one row per variable
    rows = items(J)
    Jsym = reduce(vcat, [permutedims([Num(to_symbolics(e)) for e in (r isa AbstractVector ? r : items(r))]) for r in rows])
    svars = [Num(to_symbolics(ge(v))) for v in vars]
    f = Symbolics.build_function(Jsym, svars; expression = Val(false))[1]
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
    # antiderivatives
    "x^3 e^(2x)" => task(() -> ge("integrate(x^3*exp(2*x),x)")),
    "1/(x^3+1)" => task(() -> ge("integrate(1/(x^3+1),x)")),
    "sec^3 x" => task(() -> ge("integrate(1/cos(x)^3,x)")),
    "x/(x^4+1)" => task(() -> ge("integrate(x/(x^4+1),x)")),
    "ln(x)^2/x^2" => task(() -> ge("integrate(ln(x)^2/x^2,x)")),
    "e^x sin x" => task(() -> ge("integrate(exp(x)*sin(x),x)")),
    "sqrt(1-x^2)" => task(() -> ge("integrate(sqrt(1-x^2),x)")),
    "1/(x sqrt(x^2-1))" => task(() -> (ge("assume(x>1)"); ge("integrate(1/(x*sqrt(x^2-1)),x)"))),
    "x asin x" => task(() -> ge("integrate(x*asin(x),x)")),
    "1/(2+cos x)" => task(() -> ge("integrate(1/(2+cos(x)),x)")),
    # definite integrals
    "Dalzell's integral" => task(() -> ge("integrate(x^4*(1-x)^4/(1+x^2),x,0,1)")),
    "Dirichlet's integral" => task(() -> ge("integrate(sin(x)/x,x,0,+infinity)")),
    "The Gaussian integral" => task(() -> ge("integrate(exp(-x^2),x,0,+infinity)")),
    "A logarithm over 1-x" => task(() -> ge("integrate(ln(x)/(1-x),x,0,1)")),
    "A power of the sine" => task(() -> ge("integrate(sin(x)^4,x,0,pi)")),
    "Planck's integral" => task(() -> ge("integrate(x^3/(exp(x)-1),x,0,+infinity)")),
    "x ln(1+x) on [0,1]" => task(() -> ge("integrate(x*ln(1+x),x,0,1)")),
    "A quartic denominator on the line" => task(() -> ge("integrate(1/(x^4+1),x,-infinity,+infinity)")),
    "A damped sine" => task(() -> ge("integrate(x*exp(-x)*sin(x),x,0,+infinity)")),
    # series and products
    "zeta(6)" => task(() -> ge("sum(1/n^6,n,1,+infinity)")),
    "n^3/3^n" => task(() -> ge("sum(n^3/3^n,n,1,+infinity)")),
    "The alternating harmonic series" => task(() -> ge("sum((-1)^(n+1)/n,n,1,+infinity)")),
    "A telescoping sum" => task(() -> ge("sum(1/(n*(n+1)*(n+2)),n,1,+infinity)")),
    "Leibniz's series" => task(() -> ge("sum((-1)^n/(2*n+1),n,0,+infinity)")),
    "The binomial theorem at 2" => task(() -> ge("sum(comb(n,k)*2^k,k,0,n)")),
    "Nicomachus's theorem" => task(() -> ge("sum(k^3,k,1,n)")),
    "1/(4n^2-1)" => task(() -> ge("sum(1/(4*n^2-1),n,1,+infinity)")),
    "A product equal to 2" => task(() -> ge("product((n+1)^2/(n*(n+2)),n,1,+infinity)")),
    # limits
    "(e^x-1-x)/x^2" => task(() -> ge("limit((exp(x)-1-x)/x^2,x,0)")),
    "(1-cos x)/x^2" => task(() -> ge("limit((1-cos(x))/x^2,x,0)")),
    "(1+2/x)^x" => task(() -> ge("limit((1+2/x)^x,x,+infinity)")),
    "x^x at 0" => task(() -> ge("limit(x^x,x,0,1)")),
    "(sin x - x)/x^3" => task(() -> ge("limit((sin(x)-x)/x^3,x,0)")),
    "n(2^(1/n)-1)" => task(() -> ge("limit(n*(2^(1/n)-1),n,+infinity)")),
    "sqrt(x^2+x)-x" => task(() -> ge("limit(sqrt(x^2+x)-x,x,+infinity)")),
    "(tan x - x)/x^3" => task(() -> ge("limit((tan(x)-x)/x^3,x,0)")),
    "1/x - 1/(e^x-1)" => task(() -> ge("limit(1/x-1/(exp(x)-1),x,0)")),
    # equations and inequalities
    "A cubic with integer roots" => task(() -> numbers("solve(x^3-6*x^2+11*x-6=0,x)")),
    "Sum and product" => task(() -> solution_tuples("solve([x+y=5,x*y=6],[x,y])")),
    "A biquadratic" => task(() -> numbers("solve(x^4-10*x^2+1=0,x)")),
    "An exponential equation" => task(() -> numbers("solve(2^x=3^(x-1),x)")),
    "A circle and a line" => task(() -> solution_tuples("solve([x^2+y^2=25,x-y=1],[x,y])")),
    "A cubic with one real root" => task(() -> numbers("csolve(x^3+x-1=0,x)")),
    "A quadratic inequality" => task(() -> ge("solve(x^2-3*x+2<0,x)")),
    "An absolute value inequality" => task(() -> ge("solve(abs(2*x-3)<5,x)")),
    # polynomials
    "x^8-1 over Q" => task(() -> FACTOR(ge("x^8-1"))),
    "Sophie Germain's identity" => task(() -> FACTOR(ge("x^4+4"))),
    "x^3+y^3+z^3-3xyz" => task(() -> FACTOR(ge("x^3+y^3+z^3-3*x*y*z"))),
    "A polynomial gcd" => task(() -> ge("gcd(x^4-1,x^6-1)")),
    "A resultant" => task(() -> ge("resultant(x^2+y^2-1,x-y,y)")),
    "A discriminant" => task(() -> ge("discriminant(x^3+p*x+q,x)")),
    "A partial fraction decomposition" => task(() -> ge("partfrac(1/((x-1)*(x+2)^2),x)")),
    "Two conics" => task(() -> solution_tuples("solve([x^2+y^2=1,x*y=1/4],[x,y])")),
    # simplification
    "A nested radical" => task(() -> ge("simplify(sqrt(7+4*sqrt(3))-2-sqrt(3))")),
    "The Pythagorean identity" => task(() -> ge("simplify(sin(x)^2+cos(x)^2-1)")),
    "A removable singularity" => task(() -> ge("simplify((x^3-1)/(x-1)-x^2-x-1)")),
    "The golden cosine" => task(() -> ge("simplify(cos(pi/5)-(1+sqrt(5))/4)")),
    "tan(pi/12)" => task(() -> ge("simplify(tan(pi/12)-2+sqrt(3))")),
    "A minimal polynomial of degree six" => task(() -> ge("poly2symb(pmin(sqrt(2)+3^(1/3)),x)")),
    "An exponential of a logarithm" => task(() -> (ge("assume(x>0)"); ge("simplify(exp(2*ln(x))-x^2)"))),
    "Zero identity: nested square root" => task(() -> ge("simplify(sqrt(3+2*sqrt(2))-1-sqrt(2))")),
    "Zero identity: nested cube root" => task(() -> ge("simplify((7+5*sqrt(2))^(1/3)-1-sqrt(2))")),
    "Zero identity: logarithms on positive reals" => task(() -> ge("simplify(ln(2)+ln(3)-ln(6))")),
    "Zero identity: exponential of a logarithm" => task(() -> ge("simplify(exp(ln(2))-2)")),
    "Zero identity: sine at pi over six" => task(() -> ge("simplify(sin(pi/6)-1/2)")),
    "Nonzero control: rational residual" => task(() -> ge("simplify(sqrt(2)^2-2+1/10^30)")),
    "Nonzero control: near integer" => task(() -> ge("simplify(exp(pi*sqrt(163))-262537412640768744)")),
    # differential equations
    "A harmonic oscillator" => task(() -> ode("y''+4*y=0", ["diff(Y,x,2)+4*Y"])),
    "A forced linear equation" => task(() -> ode("y''-3*y'+2*y=exp(3*x)", ["diff(Y,x,2)-3*diff(Y,x)+2*Y-exp(3*x)"])),
    "A first-order linear equation" => task(() -> ode("y'+2*x*y=x", ["diff(Y,x)+2*x*Y-x"])),
    "A first-order Euler equation" => task(() -> ode("x*y'-y=x^2", ["x*diff(Y,x)-Y-x^2"])),
    "A polynomial forcing" => task(() -> ode("y''+y=x", ["diff(Y,x,2)+Y-x"])),
    "A separable equation" => task(() -> ode("y'=y^2", ["diff(Y,x)-Y^2"])),
    "An initial-value problem" => task(() -> ode("[y''+y'-2*y=0,y(0)=1,y'(0)=0]",
        ["diff(Y,x,2)+diff(Y,x)-2*Y", "subst(Y,x=0)-1", "subst(diff(Y,x),x=0)"])),
    "A repeated characteristic root" => task(() -> ode("y''-2*y'+y=0", ["diff(Y,x,2)-2*diff(Y,x)+Y"])),
    # linear algebra
    "A tridiagonal determinant" => task(() -> ge("det([[2,1,0],[1,2,1],[0,1,2]])")),
    "A 2x2 inverse" => task(() -> jmatrix("inv([[4,7],[2,6]])")),
    "Eigenvalues of a symmetric matrix" => task(() -> real.(numbers("[eigenvals([[2,1],[1,2]])]"))),
    "The rank of a singular matrix" => task(() -> ge("rank([[1,2,3],[4,5,6],[7,8,9]])")),
    "A linear system" => task(() -> real.(numbers("linsolve([2*x+y-z=8,-3*x-y+2*z=-11,-2*x+y+2*z=-3],[x,y,z])"))),
    "A characteristic polynomial" => task(() -> ge("charpoly([[1,2],[3,4]],x)")),
    "A Fibonacci matrix power" => task(() -> jmatrix("[[1,1],[1,0]]^10")),
    "A symbolic determinant" => task(() -> ge("det([[a,b],[b,a]])")),
    # number theory
    "The Fermat number F6" => task(() -> (L = items(ge("ifactors(2^64+1)")); [big(tj(L[i])) for i in 1:2:length(L)])),
    "A Mersenne prime of 89 bits" => task(() -> ge("isprime(2^89-1)")),
    "A gcd of Mersenne numbers" => task(() -> ge("gcd(2^60-1,2^84-1)")),
    "A modular inverse" => task(() -> ge("irem(iegcd(17,3120)[0],3120)")),
    "Euler's totient of a million" => task(() -> ge("euler(10^6)")),
    "The next prime after 10^12" => task(() -> ge("nextprime(10^12)")),
    "The Chinese remainder theorem" => task(() -> ge("ichinrem(ichinrem([2,3],[3,5]),[2,7])[0]")),
    "A sum of divisors" => task(() -> ge("sum(idivis(360))")),
    # transforms and series expansions
    "A Laplace transform" => task(() -> ge("laplace(t*exp(-2*t),t,s)")),
    "An inverse Laplace transform" => task(() -> ge("ilaplace(1/(s^2+4),s,t)")),
    "The Laplace transform of a cosine" => task(() -> ge("laplace(cos(2*t),t,s)")),
    "Gamma at one half" => task(() -> ge("Gamma(1/2)")),
    "A Beta value" => task(() -> ge("Beta(2,3)")),
    "Gamma at five halves" => task(() -> ge("Gamma(5/2)")),
    "The series of tan" => task(() -> ge("convert(series(tan(x),x=0,8),polynom)")),
    "The series of e^x sin x" => task(() -> ge("convert(series(exp(x)*sin(x),x=0,5),polynom)")),
    # model to Jacobian
    "Jacobian: Brusselator N=10 (build)" => task(() -> jacobian_fn(10)),
    "Jacobian: Brusselator N=50 (build)" => task(() -> jacobian_fn(50)),
    "Jacobian: Brusselator N=10 (evaluate 1000 points)" => task(() -> jacobian_eval(10)),
    "Jacobian: Brusselator N=50 (evaluate 1000 points)" => task(() -> jacobian_eval(50)),
)
