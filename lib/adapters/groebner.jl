# Groebner.jl adapter (bench G): polynomials built in an AbstractAlgebra ring,
# `groebner` with the default options (reduced basis, degrevlex ring order).
using Groebner, AbstractAlgebra

const SYSTEM = "Groebner.jl"
const VAR = Dict{Symbol,Any}()

isdefined(Main, :Poly) || include(joinpath(@__DIR__, "..", "poly.jl"))

function build(R, strs::Vector{String}, vars::Vector{String}, p::Int)
    K = base_ring(R)
    map(strs) do s
        f = Poly.parse_poly(s, vars)
        C = MPolyBuildCtx(R)
        for (m, c) in f
            push_term!(C, p == 0 ? K(numerator(c), denominator(c)) : K(Poly.modp(c, p)), m)
        end
        finish(C)
    end
end

function GROEBNER(polys::Vector{String}, vars::Vector{String}, p::Int)
    R, _ = polynomial_ring(p == 0 ? QQ : GF(p), vars; internal_ordering = :degrevlex)
    gb = groebner(build(R, polys, vars, p))
    [string(g) for g in gb]
end

const OPS = Dict{Symbol,Any}(:groebner => GROEBNER)
EVAL(ex, vals) = ex isa Number ? ex : nothing
NTERMS(ex) = 1
NFACTORS(ex) = 1
UNSOLVED(op, out) = out isa AbstractVector && isempty(out)
CLEARCACHE() = nothing
VERSIONS() = ["Groebner" => string(pkgversion(Groebner)), "AbstractAlgebra" => string(pkgversion(AbstractAlgebra))]
