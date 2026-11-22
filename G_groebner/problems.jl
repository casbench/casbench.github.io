# Bench G: reduced Gröbner bases (degrevlex) of classical polynomial systems
# over Q and over the prime field GF(1073741827), for Giac.jl (`gbasis`),
# Groebner.jl, msolve through AlgebraicSolving.jl, and SymPy (`groebner`).
#
# Inputs are the strings of G_groebner/inputs.jl (generated once from
# Groebner.jl's Examples). Each adapter maps :groebner to a function
# (polys::Vector{String}, vars::Vector{String}, p::Int) -> Vector{String}
# (the basis as printed by the system; p == 0 means Q).
#
# Check, in plain Julia (lib/poly.jl), on the printed basis:
#   1. it parses, and in canonical form (monic, sorted by leading monomial) it
#      is reduced: no term of a polynomial is divisible by the leading
#      monomial of another one (a reduced Gröbner basis is unique, so two
#      correct answers have the same canonical form, whose digest is in the
#      note; make_tables reports the agreement between systems);
#   2. every input polynomial reduces to zero modulo the basis, computed over
#      GF(2147483647) for the rational cases (the division algorithm).
# What is not checked here: that the basis generates no more than the ideal
# (digest agreement between independent systems mitigates but does not prove it).

isdefined(Main, :Poly) || include(joinpath(@__DIR__, "..", "lib", "poly.jl"))   # the adapters of the Julia packages include it too
include(joinpath(@__DIR__, "inputs.jl"))
# Poly is used qualified: AbstractAlgebra and Nemo export a `leading_monomial` of their own

const PRIME = 1073741827          # 2^30 + 3, the field of the modular cases
const CHECK_PRIME = 2147483647    # 2^31 - 1, used for the membership check of the rational cases

function check_gb(out, polys_in::Vector{String}, vars::Vector{String}, p::Int)
    hasfield(typeof(out), :polys) && (out = out.polys)        # the subprocess adapters wrap the basis with its timing
    out isa AbstractVector || return (:unverified, "not a list of polynomials")
    strs = [string(e) for e in out]
    polys, canon = try
        Poly.canonical_basis(strs, vars, p)
    catch e
        return (:unverified, "parse: " * first(sprint(showerror, e), 120))
    end
    isempty(polys) && return (:unsolved, "empty basis")
    k = length(polys)
    maxdeg = maximum(sum(Poly.leading_monomial(f)) for f in polys)
    nterms = sum(length, polys)
    info = "k=$k maxdeg=$maxdeg terms=$nterms sha=$(Poly.basis_digest(canon))"
    Poly.is_reduced(polys) || return (:unsolved, "not a reduced basis; " * info)
    q = p == 0 ? CHECK_PRIME : p
    fb = p == 0 ? [Poly.tofield(f, q) for f in polys] : Vector{Poly.FPoly}(polys)
    for s in polys_in
        f = Poly.tofield(Poly.parse_poly(s, vars), q)
        r, steps = Poly.reduce_mod(f, fb, q)
        isempty(r) || return (:wrong, "an input polynomial does not reduce to zero modulo the basis (mod $q); " * info)
    end
    (:verified, info)
end

const PROBLEMS = NamedTuple[]
for sys in SYSTEMS, (field, p) in (("Q", 0), ("GF(p)", PRIME))
    polys, vars = sys.polys, sys.vars
    push!(PROBLEMS, (name = "$(sys.name) over $field", op = :groebner,
                     args = V -> (polys, vars, p),
                     check = o -> check_gb(o, polys, vars, p),
                     note = "$(length(polys)) polynomials in $(length(vars)) variables, degrevlex, " *
                            (p == 0 ? "over Q" : "over GF($p)")))
end

# The base tier above stays unchanged. The hard tier runs in a separate pass
# and retains distinct case indices, so it can be merged with base results.
if get(ENV, "BENCH_G_HARD", "0") == "1"
    include(joinpath(@__DIR__, "hard_inputs.jl"))
    for sys in HARD_SYSTEMS
        polys, vars = sys.polys, sys.vars
        push!(PROBLEMS, (name = "$(sys.name) over Q (hard tier)", op = :groebner, budget = sys.budget,
                         args = V -> (polys, vars, 0),
                         check = o -> check_gb(o, polys, vars, 0),
                         note = "hard tier; per-case budget $(sys.budget) s; " *
                                "$(length(polys)) polynomials in $(length(vars)) variables, degrevlex, over Q"))
    end
end
