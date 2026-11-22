# msolve adapter (bench G), through AlgebraicSolving.jl: polynomials built in
# a Nemo ring, `groebner_basis` of the ideal (msolve's F4, reduced basis,
# degrevlex). Over Q, AlgebraicSolving lifts a modular computation.
using AlgebraicSolving, Nemo

const SYSTEM = "msolve (AlgebraicSolving.jl)"
const VAR = Dict{Symbol,Any}()

isdefined(Main, :Poly) || include(joinpath(@__DIR__, "..", "poly.jl"))

function build(R, strs::Vector{String}, vars::Vector{String}, p::Int)
    K = base_ring(R)
    map(strs) do s
        f = Poly.parse_poly(s, vars)
        C = MPolyBuildCtx(R)
        for (m, c) in f
            push_term!(C, p == 0 ? K(numerator(c)) // K(denominator(c)) : K(Poly.modp(c, p)), m)
        end
        finish(C)
    end
end

function GROEBNER(polys::Vector{String}, vars::Vector{String}, p::Int)
    R, _ = polynomial_ring(p == 0 ? Nemo.QQ : Nemo.GF(p), vars; internal_ordering = :degrevlex)
    I = AlgebraicSolving.Ideal(build(R, polys, vars, p))
    gb = AlgebraicSolving.groebner_basis(I)
    [string(g) for g in gb]
end

const OPS = Dict{Symbol,Any}(:groebner => GROEBNER)
EVAL(ex, vals) = ex isa Number ? ex : nothing
NTERMS(ex) = 1
NFACTORS(ex) = 1
UNSOLVED(op, out) = out isa AbstractVector && isempty(out)
CLEARCACHE() = nothing
VERSIONS() = ["AlgebraicSolving" => string(pkgversion(AlgebraicSolving)), "Nemo" => string(pkgversion(Nemo)),
              "msolve_jll" => string(pkgversion(AlgebraicSolving.msolve_jll))]

# RUR plus the real solutions isolated by msolve.  The checker independently
# substitutes every reported real solution and checks the rational lifting map.
function RUR(polys::Vector{String}, vars::Vector{String})
    R, _ = polynomial_ring(Nemo.QQ, vars; internal_ordering = :degrevlex)
    I = AlgebraicSolving.Ideal(build(R, polys, vars, 0))
    solutions = AlgebraicSolving.real_solutions(I; precision=256)
    r = I.rat_param
    coeffs(p) = [BigInt(numerator(coeff(p, i))) // BigInt(denominator(coeff(p, i))) for i in 0:degree(p)]
    (vars=string.(r.vars), linear_form=string.(r.cfs_lf), elim=coeffs(r.elim),
     denom=coeffs(r.denom), param=[coeffs(p) for p in r.param],
     solutions=[[BigInt(numerator(x)) // BigInt(denominator(x)) for x in sol] for sol in solutions])
end
OPS[:rur] = RUR
