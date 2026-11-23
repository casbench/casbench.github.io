using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
root = normpath(joinpath(@__DIR__, ".."))

@testset "supervised interface paths" begin
    mktempdir() do dir
        supervisor = joinpath(root, "lib", "supervise.jl")
        worker = joinpath(root, "lib", "worker.jl")
        fake = joinpath(root, "test", "fake_interface_process.py")
        # Run the matching first case for persistent and new-process paths.
        for system in ("maxima", "fricas"), (i, mode) in ((9, "interface_session"), (13, "interface_cold"))
            out = joinpath(dir, "A_interfaces_$(system).tsv")
            starts = joinpath(dir, "$(system)_$(mode)_starts")
            withenv("MAXIMA" => fake, "FRICAS" => fake, "FAKE_INTERFACE_STARTS" => starts,
                    "BENCH_START_INDEX" => string(i), "BENCH_STOP" => string(i), "BENCH_RESUME" => "0") do
                run(`$(Base.julia_cmd()) --startup-file=no $supervisor $root $worker A_interfaces $system $out 60`)
            end
            r = last(read_records(out))
            @test (r.idx, r.op, r.status) == (i, mode, "verified_numeric")
            @test isfinite(r.t_first) && isfinite(r.t_warm)
            @test occursin("(x+y)^2", r.input)
            @test occursin("x^2", r.result)
            count = length(readlines(starts))
            @test mode == "interface_session" ? count == 1 : count > 1
        end
        hung = joinpath(dir, "hung.tsv")
        withenv("MAXIMA" => fake, "FAKE_INTERFACE_HANG" => "1", "BENCH_START_INDEX" => "9", "BENCH_STOP" => "9") do
            run(`$(Base.julia_cmd()) --startup-file=no $supervisor $root $worker A_interfaces maxima $hung 3`)
        end
        r = only(read_records(hung))
        @test r.status == "timeout"
        @test occursin("(x+y)^2", r.input)
    end
end
