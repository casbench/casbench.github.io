using Test
ENV["BENCH_G_HARD"] = "1"
include(joinpath(@__DIR__, "..", "G_groebner", "problems.jl"))
@testset "hard tier follows the unchanged base tier" begin
    @test length(PROBLEMS) == 37
    @test length(SYSTEMS) * 2 == 32
    @test [p.name for p in PROBLEMS[33:end]] == ["cyclic8 over Q (hard tier)", "cyclic9 over Q (hard tier)", "katsura10 over Q (hard tier)", "eco11 over Q (hard tier)", "eco12 over Q (hard tier)"]
    @test [p.budget for p in PROBLEMS[33:end]] == [600, 3600, 600, 600, 600]
    for p in PROBLEMS[33:end]
        polys, vars, prime = p.args(nothing)
        @test prime == 0 && length(polys) == length(vars)
        @test all(s -> !isempty(Poly.parse_poly(s, vars)), polys)
    end
end
