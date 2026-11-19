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
