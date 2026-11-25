# Sage/Giac Gröbner bases over Q: Giac's probabilistic algorithm prints the
# note "error probability is less than 1e-15", which Sage's giac interface took
# for an error. katsura7 over Q was "sage gave no basis" on 2026-11-19; it must
# now give the reduced basis the check accepts, also for a command long enough
# to go through a file (katsura10), and a genuine Giac error must still raise. Needs `sage` and `giac` on PATH (the Nix toolchain).
#
#   julia --project=envs/subprocess test/sage_giac_groebner.jl
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
const SAGE_ALGORITHM = "giac"
include(joinpath(@__DIR__, "..", "lib", "adapters", "sage.jl"))
include(joinpath(@__DIR__, "..", "G_groebner", "problems.jl"))

@testset "Sage/Giac Gröbner bases over Q" begin
    k7 = only(s for s in SYSTEMS if s.name == "katsura7")
    B = GROEBNER(k7.polys, k7.vars, 0)
    @test length(B.polys) > 1
    st = check_gb(B, k7.polys, k7.vars, 0)
    @test (st isa Tuple ? st[1] : st) == :verified
    c4 = only(s for s in SYSTEMS if s.name == "cyclic4")
    st = check_gb(GROEBNER(c4.polys, c4.vars, PRIME), c4.polys, c4.vars, PRIME)
    @test (st isa Tuple ? st[1] : st) == :verified
    @test_throws Exception GROEBNER(["x^+"], ["x"], 0)
    # a long command goes through a file: katsura10 over Q (hard tier) was still "sage gave no basis" at 7a951bc
    include(joinpath(@__DIR__, "..", "G_groebner", "hard_inputs.jl"))
    k10 = only(s for s in HARD_SYSTEMS if s.name == "katsura10")
    B10 = GROEBNER(k10.polys, k10.vars, 0)
    st = check_gb(B10, k10.polys, k10.vars, 0)
    @test (st isa Tuple ? st[1] : st) == :verified
end
