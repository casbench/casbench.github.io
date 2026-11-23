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

    interface_output = joinpath(dir, "A_interfaces_giac.tsv")
    withenv("BENCH_STOP" => "2", "BENCH_RESUME" => "0") do
        run(`$(Base.julia_cmd()) --startup-file=no $supervisor $envdir $worker A_interfaces giac $interface_output 90`)
    end
    interface_rows = filter(r -> r.idx > 0, read_records(interface_output))
    @test length(interface_rows) == 2
    @test all(r -> r.op == "interface_object" && r.status == "verified_numeric", interface_rows)
    @test all(r -> occursin("expand", r.input) && !isempty(r.result), interface_rows)
    withenv("BENCH_START_INDEX" => "5", "BENCH_STOP" => "6", "BENCH_RESUME" => "0") do
        run(`$(Base.julia_cmd()) --startup-file=no $supervisor $envdir $worker A_interfaces giac $interface_output 90`)
    end
    text_rows = filter(r -> r.idx in (5, 6), read_records(interface_output))
    @test length(text_rows) == 2
    @test all(r -> r.op == "interface_text" && r.status == "verified_numeric", text_rows)
    @test all(r -> occursin("expand", r.input) && !isempty(r.result), text_rows)
end
