using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
EVAL(f::Function, point) = f(point[:x])
bench = only(ARGS)
bench in ("F_integration", "H_osr") || error("unknown integration bench")
include(joinpath(@__DIR__, "..", bench, "problems.jl"))
@testset "$bench task check interface" begin
    @test !isempty(PROBLEMS)
    p = first(PROBLEMS)
    @test p.real_points == FPOINTS
    status, note = p.check(x -> 0.0)
    @test status in (:wrong, :unverified, :unsolved, :verified_numeric)
    @test note isa AbstractString
end
