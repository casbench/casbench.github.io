# A subprocess adapter (FriCAS, Maxima, Macaulay2) runs its system under
# `timeout BENCH_CASE_TIMEOUT`, a safety net in case the worker dies. When that
# limit equalled the supervisor's case budget, the two raced: if the
# subprocess's own `timeout` fired first, the worker read an empty output and
# recorded "fricas gave no answer" (an error) instead of a timeout (host-2,
# 23 and 26 November 2026: H 482 to 490 for FriCAS flipped between the two).
# The limit seen by the subprocess must exceed the case budget, so that the
# supervisor always stops the case first.
#
# Runs the real supervisor and worker on F case 1 with a fake system that
# reports the limit it was given and never answers.
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
root = normpath(joinpath(@__DIR__, ".."))
const BUDGET = 3

mktempdir() do dir
    seen = joinpath(dir, "limit-seen")
    fake = joinpath(dir, "fake-system")
    write(fake, """
        #!/usr/bin/env bash
        case "\$*" in *version*) echo "fake 0.0"; exit 0;; esac
        echo "\$BENCH_CASE_TIMEOUT" >> "$seen"
        echo "banner of a system that never answers"
        exec sleep 120
        """)
    chmod(fake, 0o755)
    supervisor = joinpath(root, "lib", "supervise.jl")
    worker = joinpath(root, "lib", "worker.jl")
    for (system, var) in (("fricas", "FRICAS"), ("maxima", "MAXIMA"))
        rm(seen; force = true)
        out = joinpath(dir, "F_integration_$system.tsv")
        withenv(var => fake, "BENCH_START_INDEX" => "1", "BENCH_STOP" => "1", "BENCH_RESUME" => "0") do
            run(`$(Base.julia_cmd()) --startup-file=no $supervisor $(joinpath(root, "envs", "subprocess")) $worker F_integration $system $out $BUDGET`)
        end
        rows = filter(r -> r.idx == 1, read_records(out))
        @testset "$system" begin
            @test length(rows) == 1
            @test rows[1].status == "timeout"
            limits = parse.(Float64, readlines(seen))
            @test !isempty(limits) && all(>(BUDGET), limits)
        end
    end
end
