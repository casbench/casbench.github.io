# Bench D: functional coverage. One problem per capability. The three "headline"
# problems of the JuliaCon 2026 talk come first (polynomial factorisation, exact
# transcendental solve, linear Diophantine equation).
#
# Statuses: verified / wrong / unverified / unsolved / unavailable / error / timeout.
# "unavailable" means the adapter has no operation of that kind for the system
# (OPS[op] === missing), which is the coverage information this bench is about.

using .BenchCommon: POINTS, POINTS_POS, numeq

evalat(out, pt) = EVAL(out, pt)

function check_equal(out, ref; pts = POINTS)
    for pt in pts
        v = evalat(out, pt)
        v === nothing && return :unverified
        numeq(v, ref(pt)) || return :wrong
    end
    :verified
end

# a set of solutions must contain every expected real value (and nothing wrong)
function check_solutions(out, expected::Vector{Float64}; exact = false)
    out isa AbstractVector || (out = [out])
    vals = Float64[]
    for o in out
        v = evalat(o, Dict{Symbol,Float64}())
        v === nothing && return :unverified
        push!(vals, real(v))
    end
    all(e -> any(v -> numeq(v, e; rtol = 1e-8), vals), expected) || return :wrong
    exact && !all(IS_EXACT, out) && return :wrong
    :verified
end

function check_diophantine(out, lhs::Function, rhs::Float64)
    ue, ve, param = out
    for kk in (0.0, 1.0, 2.0, -3.0)
        pt = Dict(Symbol(string(param)) => kk, :k => kk)
        uu, vv = evalat(ue, pt), evalat(ve, pt)
        (uu === nothing || vv === nothing) && return :unverified
        (isinteger(round(uu; digits = 8)) && isinteger(round(vv; digits = 8))) || return :wrong
        numeq(lhs(uu, vv), rhs) || return :wrong
    end
    :verified
end

function check_factor_count(out, ref, nfactors)
    unit, fs = out
    length(fs) == nfactors || return length(fs) < nfactors ? :unsolved : :wrong
    for pt in POINTS
        p = evalat(unit, pt)
        p === nothing && return :unverified
        for (g, m) in fs
            v = evalat(g, pt)
            v === nothing && return :unverified
            p *= v^m
        end
        numeq(p, ref(pt)) || return :wrong
    end
    :verified
end

function check_series(out, ref, order)
    # the polynomial must agree with exp near 0 to the given order: at h = 0.5 the
    # truncation error of the order-6 Taylor polynomial of exp is 1.5e-6, that of
    # the order-5 one is 2e-5, so the tolerances below separate the two
    for (h, tol) in ((0.5, 4e-6), (0.25, 3.5e-8))
        v = evalat(out, Dict(:x => h))
        v === nothing && return :unverified
        abs(v - ref(h)) <= tol || return :wrong
    end
    :verified
end

function check_list(out, refs::Vector; pts = POINTS)
    out isa AbstractVector || return :unverified
    length(out) == length(refs) || return :wrong
    vals = sort([real(evalat(o, Dict{Symbol,Float64}())) for o in out])
    all(v -> v !== nothing, vals) || return :unverified
    all(i -> numeq(vals[i], sort(refs)[i]), eachindex(refs)) ? :verified : :wrong
end

function check_groebner(out, nexpected)
    # every element of the basis vanishes on the common zero (1, 1) of the ideal below
    out isa AbstractVector || return :unverified
    for g in out
        v = evalat(g, Dict(:x => 1.0, :y => 1.0))
        v === nothing && return :unverified
        numeq(v, 0.0; atol = 1e-9) || return :wrong
    end
    :verified
end

function check_ifactor(out, nn::BigInt)
    pairs = Pair{BigInt,Int}[]
    if out isa AbstractVector && !isempty(out) && !(first(out) isa Pair)
        for i in 1:2:length(out)
            push!(pairs, parse(BigInt, string(out[i])) => Int(out[i + 1]))
        end
    else
        for (p, e) in out
            push!(pairs, parse(BigInt, string(p)) => Int(e))
        end
    end
    prod(p^e for (p, e) in pairs; init = big(1)) == nn || return :wrong
    length(pairs) == 2 ? :verified : :wrong
end

P(name, op, args, check, note = "") = (name = name, op = op, args = args, check = check, note = note)

const PROBLEMS = [
    # ---- the talk's three headline problems -------------------------------------
    P("factor x^4-1", :factor, V -> (V[:x]^4 - 1,),
      o -> check_factor_count(o, p -> p[:x]^4 - 1, 3)),
    P("solve cos(x)=1/2 exactly", :solve, V -> (cos(V[:x]), 1 // 2, V[:x]),
      o -> check_solutions(o, [pi / 3]; exact = true),
      "verified = pi/3 is returned symbolically (not as a float)"),
    P("isolve 21u+28v=7", :diophantine, V -> (21V[:u] + 28V[:v], 7, V[:u], V[:v], V[:k]),
      o -> check_diophantine(o, (uu, vv) -> 21uu + 28vv, 7.0)),
    # ---- transforms --------------------------------------------------------------
    P("laplace exp(-2t) sin(3t)", :laplace, V -> (exp(-2V[:t]) * sin(3V[:t]), V[:t], V[:s]),
      o -> check_equal(o, p -> 3 / (p[:s]^2 + 4p[:s] + 13); pts = POINTS_POS)),
    P("ilaplace 1/(s^2+1)", :ilaplace, V -> (1 / (V[:s]^2 + 1), V[:s], V[:t]),
      o -> check_equal(o, p -> sin(p[:t]); pts = POINTS_POS)),
    P("ztrans n", :ztrans, V -> (V[:n], V[:n], V[:z]),
      o -> check_equal(o, p -> p[:z] / (p[:z] - 1)^2; pts = [Dict(:z => 2.5), Dict(:z => 3.7)])),
    P("partfrac x/(x^2-1)", :partfrac, V -> (V[:x] / (V[:x]^2 - 1), V[:x]),
      o -> (st = check_equal(o, p -> p[:x] / (p[:x]^2 - 1)); st === :verified ? (NTERMS(o) == 2 ? :verified : :wrong) : st)),
    # ---- calculus ----------------------------------------------------------------
    P("desolve y'=-2y, y(0)=1", :desolve_ivp, V -> ("y'", yy -> -2 * yy, "y", V[:t], 1),
      o -> check_equal(o, p -> exp(-2p[:t]); pts = POINTS_POS)),
    P("limit sin(x)/x at 0", :limit, V -> (sin(V[:x]) / V[:x], V[:x], 0),
      o -> check_equal(o, p -> 1.0)),
    P("limit (1+1/x)^x at inf", :limit, V -> ((1 + 1 / V[:x])^V[:x], V[:x], Inf),
      o -> check_equal(o, p -> exp(1.0))),
    P("series exp(x) order 6", :series, V -> (exp(V[:x]), V[:x], 6),
      o -> check_series(o, exp, 6)),
    P("sum k^2, k=1..n closed form", :sum, V -> (V[:k]^2, V[:k], 1, V[:n]),
      o -> check_equal(o, p -> p[:n] * (p[:n] + 1) * (2p[:n] + 1) / 6; pts = [Dict(:n => 3.0), Dict(:n => 10.0)])),
    P("integrate exp(-x^2) (erf)", :integrate, V -> (exp(-V[:x]^2), V[:x]),
      o -> begin
          h = 1e-5
          for pt in POINTS_POS
              fp = evalat(o, Dict(:x => pt[:x] + h)); fm = evalat(o, Dict(:x => pt[:x] - h))
              (fp === nothing || fm === nothing) && return :unverified
              numeq((fp - fm) / 2h, exp(-pt[:x]^2); rtol = 1e-6, atol = 1e-8) || return :wrong
          end
          :verified
      end),
    # ---- polynomial algebra --------------------------------------------------------
    P("gcd (x^2-1)(x+2), (x+1)(x+2)^2", :gcd, V -> ((V[:x]^2 - 1) * (V[:x] + 2), (V[:x] + 1) * (V[:x] + 2)^2),
      o -> check_equal(o, p -> (p[:x] + 1) * (p[:x] + 2)), "verified up to the unit: gcd compared numerically to (x+1)(x+2)"),
    P("resultant x^2+ax+1, x^2+bx+1", :resultant, V -> (V[:x]^2 + V[:a] * V[:x] + 1, V[:x]^2 + V[:b] * V[:x] + 1, V[:x]),
      o -> check_equal(o, p -> (p[:a] - p[:b])^2)),
    P("discriminant ax^2+bx+c", :discriminant, V -> (V[:a] * V[:x]^2 + V[:b] * V[:x] + V[:c], V[:x]),
      o -> check_equal(o, p -> p[:b]^2 - 4p[:a] * p[:c])),
    P("groebner [x^2+y^2-2, x-y]", :groebner, V -> ([V[:x]^2 + V[:y]^2 - 2, V[:x] - V[:y]], [V[:x], V[:y]]),
      o -> check_groebner(o, 2)),
    P("cfactor x^2+1 over C", :cfactor, V -> (V[:x]^2 + 1,),
      o -> (s = string(o); (occursin("i", s) || occursin("I", s) || occursin("im", s)) ? :unverified : :wrong),
      "unverified = a factorisation involving i was returned; not checked numerically"),
    # ---- linear algebra -------------------------------------------------------------
    P("det [[a,b],[c,x]]", :det, V -> ([[V[:a], V[:b]], [V[:c], V[:x]]],),
      o -> check_equal(o, p -> p[:a] * p[:x] - p[:b] * p[:c])),
    P("eigenvals [[a,1],[1,a]]", :eigenvals, V -> ([[V[:a], 1], [1, V[:a]]],),
      o -> begin
          o isa AbstractVector || return :unverified
          vals = [evalat(e, Dict(:a => 1.7)) for e in o]
          any(v -> v === nothing, vals) && return :unverified
          (any(v -> numeq(real(v), 2.7), vals) && any(v -> numeq(real(v), 0.7), vals)) ? :verified : :wrong
      end),
    # ---- number theory -----------------------------------------------------------------
    P("ifactor 60-digit semiprime", :ifactor,
      V -> (big"632459103267572196107100983820469021721602147490918660274601",),
      o -> check_ifactor(o, big"632459103267572196107100983820469021721602147490918660274601"),
      "two 30-digit primes; see bench C for timings"),
    # ---- assumptions ---------------------------------------------------------------------
    P("simplify sqrt(x^2) with x>0", :assume_simplify, V -> (sqrt(V[:x]^2), V[:x]),
      o -> (s = replace(string(o), " " => ""); s in ("x",) ? :verified : (check_equal(o, p -> p[:x]; pts = POINTS_POS) === :verified ? :unsolved : :wrong)),
      "verified = the answer is exactly x; unsolved = numerically right but not reduced to x"),
    P("trigsimp sin(2x)-2sin(x)cos(x)", :trigsimp, V -> (sin(2V[:x]) - 2sin(V[:x]) * cos(V[:x]),),
      o -> (replace(string(o), " " => "") == "0" ? :verified : (check_equal(o, p -> 0.0) === :verified ? :unsolved : :wrong))),
]
