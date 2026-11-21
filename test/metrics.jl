using Test
include(joinpath(@__DIR__, "..", "lib", "metrics.jl"))
using .BenchMetrics

row(status, time; idx=1, op="expand", first=time) =
    (idx=idx, op=op, status=status, t_warm=time, t_first=first)

@testset "operation metrics" begin
    r = [row("verified", 1.0), row("verified", 3.0), row("verified", 9.0),
         row("timeout", 999.0), row("unavailable", 10.0), row("verified", 100.0; idx=0)]
    m = operation_metrics(r)
    @test (m.solved, m.attempted, m.fraction) == (3, 4, 0.75)
    @test (m.q1, m.median, m.q3) == (2.0, 3.0, 6.0)
    m = operation_metrics([row("verified", NaN; first=4.0), row("timeout", 60.0)])
    @test (m.solved, m.attempted, m.median) == (1, 2, 4.0)
    @test isnan(operation_metrics([row("verified", 2.0), row("wrong", 1.0), row("timeout", 60.0)]).median)
    @test isnan(operation_metrics([row("unavailable", NaN)]).fraction)
    @test isnan(operation_metrics([row("verified", NaN)]).median)
    @test_throws ArgumentError operation_metrics([row("verified", 1.0), row("verified", 2.0; op="factor")])
end
