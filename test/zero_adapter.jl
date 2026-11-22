# Real-adapter smoke test, run with --project=envs/<system> and the system key
# as the only argument. It exercises the precision boundary independently of
# the timing harness; no benchmark result files are written.
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
system = only(ARGS)
system in ("giac", "sympy") || error("zero-adapter test supports giac or sympy")
include(joinpath(@__DIR__, "..", "lib", "adapters", system * ".jl"))
include(joinpath(@__DIR__, "..", "E_suite", "zero_reference.jl"))

if system == "giac"
    residual = geval("sin(x)^2+cos(x)^2-1")
    nonzero = geval("1/10^30")
else
    residual = S.sympify("sin(x)**2+cos(x)**2-1"; evaluate=false)
    nonzero = S.sympify("1/10**30")
end
@testset "80-digit adapter evaluation: $system" begin
    v = setprecision(BigFloat, 256) do
        EVAL_HIGH_PRECISION(residual, 80, 7//10)
    end
    @test v !== nothing && abs(v) < big"1e-60"
    v = setprecision(BigFloat, 256) do
        EVAL_HIGH_PRECISION(nonzero, 80, nothing)
    end
    lo, hi = rational_control_interval()
    @test v !== nothing && lo <= v <= hi
    @test EVAL_HIGH_PRECISION(0.5, 80, nothing) === nothing
end
