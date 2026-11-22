using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
EVAL(f, pt) = f(pt)
include(joinpath(@__DIR__, "..", "B_cas", "problems.jl"))

@testset "simplification checks do not demand a printed form" begin
    cases = filter(p -> p.op == :simplify, PROBLEMS)
    @test length(cases) == 8
    @test cases[1].check(p -> (p[:x]^2 - 1) / (p[:x] - 1)) == :verified_numeric
    @test cases[1].check(p -> p[:x] + 2) == :wrong
    @test cases[2].check(p -> sin(p[:x])^2 + cos(p[:x])^2) == :verified_numeric
    @test cases[3].check(p -> nothing) == :unverified
end
