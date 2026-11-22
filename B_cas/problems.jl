# Bench B: expand, factor, integrate, simplify on fixed inputs.
#
# Each problem builds its arguments from the adapter's VAR dictionary so that
# the same mathematical input is given to every system. `check` receives the
# system's answer and returns :verified, :wrong or :unverified.
#
# Verification:
#   expand     numeric equality with the input at POINTS and the expected number of terms
#   factor     product of the returned factors equals the input numerically; the number of
#              non-constant factors equals the number of irreducible factors over Q
#   integrate  a central finite difference of the antiderivative matches the integrand
#              at three positive points (step 1e-5, relative tolerance 1e-6)
#   simplify   numeric equality with the input at fixed points, independent of output form
# The numeric closures `ref` are plain Julia and independent of any CAS.

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

# expansions are evaluated at positive points: at a negative point the expanded
# form of (x+1)^20 suffers catastrophic cancellation in floating point
function check_expand(out, ref, nterms)
    st = check_equal(out, ref; pts = POINTS_POS)
    st === :verified || return st
    # numerically equal but not the expected number of terms: incomplete expansion
    # (Giac's expand, for instance, can leave (-y)^3 as an atom), reported as unsolved
    NTERMS(out) == nterms ? :verified : :unsolved
end

function check_factor(out, ref, nfactors)
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

function check_integrate(out, ref)
    h = 1e-5
    for pt in POINTS_POS
        x0 = pt[:x]
        fp = evalat(out, merge(pt, Dict(:x => x0 + h)))
        fm = evalat(out, merge(pt, Dict(:x => x0 - h)))
        (fp === nothing || fm === nothing) && return :unverified
        d = (fp - fm) / (2h)
        numeq(d, ref(pt); rtol = 1e-6, atol = 1e-8) || return :wrong
    end
    :verified
end

function check_simplify(out, ref)
    # Compare the returned value with the input, without imposing a particular
    # printed representation on mathematically equivalent results.
    st = check_equal(out, ref)
    st === :verified ? :verified_numeric : st
end

P(name, op, args, check, note = "") = (name = name, op = op, args = args, check = check, note = note)

const PROBLEMS = [
    # ---- expand ---------------------------------------------------------------
    P("expand (x+y)^5", :expand, V -> ((V[:x] + V[:y])^5,),
      o -> check_expand(o, p -> (p[:x] + p[:y])^5, 6)),
    P("expand (x+y)^10", :expand, V -> ((V[:x] + V[:y])^10,),
      o -> check_expand(o, p -> (p[:x] + p[:y])^10, 11)),
    P("expand (x+y+z)^6", :expand, V -> ((V[:x] + V[:y] + V[:z])^6,),
      o -> check_expand(o, p -> (p[:x] + p[:y] + p[:z])^6, 28)),
    P("expand (x+1)^20", :expand, V -> ((V[:x] + 1)^20,),
      o -> check_expand(o, p -> (p[:x] + 1)^20, 21)),
    P("expand (x^2+3x+1)^8 (x-1)^3", :expand, V -> ((V[:x]^2 + 3V[:x] + 1)^8 * (V[:x] - 1)^3,),
      o -> check_expand(o, p -> (p[:x]^2 + 3p[:x] + 1)^8 * (p[:x] - 1)^3, 20)),
    P("expand (x+y)^3 (x-y)^3 (x+2y)^2", :expand, V -> ((V[:x] + V[:y])^3 * (V[:x] - V[:y])^3 * (V[:x] + 2V[:y])^2,),
      o -> check_expand(o, p -> (p[:x] + p[:y])^3 * (p[:x] - p[:y])^3 * (p[:x] + 2p[:y])^2, 9)),
    # ---- factor (counts are the numbers of irreducible factors over Q) ----------
    P("factor x^4-1", :factor, V -> (V[:x]^4 - 1,),
      o -> check_factor(o, p -> p[:x]^4 - 1, 3)),
    P("factor x^8-1", :factor, V -> (V[:x]^8 - 1,),
      o -> check_factor(o, p -> p[:x]^8 - 1, 4)),
    P("factor x^12-1", :factor, V -> (V[:x]^12 - 1,),
      o -> check_factor(o, p -> p[:x]^12 - 1, 6)),
    P("factor x^16-1", :factor, V -> (V[:x]^16 - 1,),
      o -> check_factor(o, p -> p[:x]^16 - 1, 5)),
    P("factor x^2 y^2-1", :factor, V -> (V[:x]^2 * V[:y]^2 - 1,),
      o -> check_factor(o, p -> p[:x]^2 * p[:y]^2 - 1, 2)),
    P("factor x^10+x^5+1", :factor, V -> (V[:x]^10 + V[:x]^5 + 1,),
      o -> check_factor(o, p -> p[:x]^10 + p[:x]^5 + 1, 2)),
    P("factor expanded (x+1)^3 (x-2)^2 (x^2+1)", :factor,
      V -> (V[:x]^7 - V[:x]^6 - 4V[:x]^5 + 3V[:x]^3 + 5V[:x]^2 + 8V[:x] + 4,),
      o -> check_factor(o, p -> (p[:x] + 1)^3 * (p[:x] - 2)^2 * (p[:x]^2 + 1), 3),
      "input is given expanded: x^7-x^6-4x^5+3x^3+5x^2+8x+4"),
    P("factor x^6-y^6", :factor, V -> (V[:x]^6 - V[:y]^6,),
      o -> check_factor(o, p -> p[:x]^6 - p[:y]^6, 4)),
    # ---- integrate (indefinite in x) -----------------------------------------
    P("integrate x exp(x)", :integrate, V -> (V[:x] * exp(V[:x]), V[:x]),
      o -> check_integrate(o, p -> p[:x] * exp(p[:x]))),
    P("integrate 1/(x^2+1)", :integrate, V -> (1 / (V[:x]^2 + 1), V[:x]),
      o -> check_integrate(o, p -> 1 / (p[:x]^2 + 1))),
    P("integrate sin(x)^2", :integrate, V -> (sin(V[:x])^2, V[:x]),
      o -> check_integrate(o, p -> sin(p[:x])^2)),
    P("integrate x^2 log(x)", :integrate, V -> (V[:x]^2 * log(V[:x]), V[:x]),
      o -> check_integrate(o, p -> p[:x]^2 * log(p[:x]))),
    P("integrate 1/(x^3+1)", :integrate, V -> (1 / (V[:x]^3 + 1), V[:x]),
      o -> check_integrate(o, p -> 1 / (p[:x]^3 + 1))),
    P("integrate x/(x^2+1)^2", :integrate, V -> (V[:x] / (V[:x]^2 + 1)^2, V[:x]),
      o -> check_integrate(o, p -> p[:x] / (p[:x]^2 + 1)^2)),
    P("integrate exp(x)/(exp(x)+1)^2", :integrate, V -> (exp(V[:x]) / (exp(V[:x]) + 1)^2, V[:x]),
      o -> check_integrate(o, p -> exp(p[:x]) / (exp(p[:x]) + 1)^2)),
    P("integrate 1/(x log(x))", :integrate, V -> (1 / (V[:x] * log(V[:x])), V[:x]),
      o -> check_integrate(o, p -> 1 / (p[:x] * log(p[:x])))),
    P("integrate sqrt(x^2+1)", :integrate, V -> (sqrt(V[:x]^2 + 1), V[:x]),
      o -> check_integrate(o, p -> sqrt(p[:x]^2 + 1))),
    P("integrate exp(-x^2)", :integrate, V -> (exp(-V[:x]^2), V[:x]),
      o -> check_integrate(o, p -> exp(-p[:x]^2)), "non-elementary (erf)"),
    P("integrate x^3 sin(x)", :integrate, V -> (V[:x]^3 * sin(V[:x]), V[:x]),
      o -> check_integrate(o, p -> p[:x]^3 * sin(p[:x]))),
    P("integrate 1/sqrt(x^2+4)", :integrate, V -> (1 / sqrt(V[:x]^2 + 4), V[:x]),
      o -> check_integrate(o, p -> 1 / sqrt(p[:x]^2 + 4))),
    # ---- simplify --------------------------------------------------------------
    P("simplify (x^2-1)/(x-1)", :simplify, V -> ((V[:x]^2 - 1) / (V[:x] - 1),),
      o -> check_simplify(o, p -> p[:x] + 1)),
    P("simplify sin^2+cos^2", :simplify, V -> (sin(V[:x])^2 + cos(V[:x])^2,),
      o -> check_simplify(o, p -> 1.0)),
    P("simplify tan(x)-sin(x)/cos(x)", :simplify, V -> (tan(V[:x]) - sin(V[:x]) / cos(V[:x]),),
      o -> check_simplify(o, p -> 0.0)),
    P("simplify (x^3-1)/(x-1)", :simplify, V -> ((V[:x]^3 - 1) / (V[:x] - 1),),
      o -> check_simplify(o, p -> p[:x]^2 + p[:x] + 1)),
    P("simplify exp(log(x))", :simplify, V -> (exp(log(V[:x])),),
      o -> check_simplify(o, p -> p[:x]), "x>0 at the test points"),
    P("simplify (a+b)^2-(a-b)^2", :simplify, V -> ((V[:a] + V[:b])^2 - (V[:a] - V[:b])^2,),
      o -> check_simplify(o, p -> 4p[:a] * p[:b])),
    P("simplify cosh^2-sinh^2", :simplify, V -> (cosh(V[:x])^2 - sinh(V[:x])^2,),
      o -> check_simplify(o, p -> 1.0)),
    P("simplify (x^2+2x+1)/(x+1)", :simplify, V -> ((V[:x]^2 + 2V[:x] + 1) / (V[:x] + 1),),
      o -> check_simplify(o, p -> p[:x] + 1)),
]
