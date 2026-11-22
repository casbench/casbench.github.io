# Real adapter smoke: run with the corresponding envs/giac or envs/msolve.
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
system = only(ARGS)
system in ("giac", "msolve", "sage_singular") || error("unknown RUR adapter")
include(joinpath(@__DIR__, "..", "lib", "adapters", system * ".jl"))
include(joinpath(@__DIR__, "..", "J_rur", "check.jl"))
@testset "RUR adapter: $system" begin
    polys, vars = ["x^5-x-1", "y-x"], ["x", "y"]
    out = RUR(polys, vars)
    @test length(out.solutions) == 1
    @test first(check_rur(out, polys, vars)) == :verified_numeric
    if system == "sage_singular"
        polys = ["x", "y^2-2"]
        out = RUR(polys, vars)
        @test length(out.solutions) == 2
        @test first(check_rur(out, polys, vars)) == :verified_numeric
        @test_throws ErrorException RUR(["x^2-2", "y"], vars)
    end
end
