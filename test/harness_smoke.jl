# A small end-to-end run through the real supervisor, worker and Giac adapter.
# Output stays in a temporary directory, never in results/.
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
root = normpath(joinpath(@__DIR__, ".."))
mktempdir() do dir
    output = joinpath(dir, "B_cas_giac.tsv")
    supervisor = joinpath(root, "lib", "supervise.jl")
    worker = joinpath(root, "lib", "worker.jl")
    envdir = joinpath(root, "envs", "giac")
    withenv("BENCH_STOP" => "2", "BENCH_RESUME" => "0") do
        run(`$(Base.julia_cmd()) --startup-file=no $supervisor $envdir $worker B_cas giac $output 90`)
    end
    rows = filter(r -> r.idx > 0, read_records(output))
    @test length(rows) == 2
    @test [r.idx for r in rows] == [1, 2]
    @test all(r -> r.status == "verified_numeric", rows)
    @test all(r -> !isempty(r.input) && !isempty(r.result) && isfinite(r.t_first), rows)
end
