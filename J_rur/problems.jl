# RUR problems reuse fixed zero-dimensional classical systems from bench G.
isdefined(Main, :Poly) || include(joinpath(@__DIR__, "..", "lib", "poly.jl"))
include(joinpath(@__DIR__, "..", "G_groebner", "inputs.jl"))
include(joinpath(@__DIR__, "check.jl"))
const PROBLEMS = NamedTuple[]
for name in ("katsura5", "cyclic5", "eco7", "noon5")
    sys = only(filter(s -> s.name == name, SYSTEMS))
    polys, vars = sys.polys, sys.vars
    push!(PROBLEMS, (name = name * " over Q", op = :rur,
                     args = V -> (polys, vars),
                     check = out -> check_rur(out, polys, vars),
                     note = "zero-dimensional classical system over Q; RUR and real solutions"))
end
