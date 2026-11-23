using Test
include(joinpath(@__DIR__, "..", "lib", "supervise.jl"))

@testset "a startup failure is not a successful run" begin
    mktempdir() do dir
        out = joinpath(dir, "result.tsv")
        worker = joinpath(@__DIR__, "fake_startup_failure.jl")
        withenv("BENCH_RESUME" => "0", "BENCH_START_INDEX" => "1") do
            @test_throws ErrorException supervise(@__DIR__, worker, "E_suite", "mock", out, 10.0, String[])
        end
        @test !isfile(out)
    end
end
