using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
include(joinpath(@__DIR__, "..", "lib", "adapters", "computeengine.jl"))
include(joinpath(@__DIR__, "..", "lib", "integration_check.jl"))
@testset "Compute Engine integral self-check" begin
    cmd = VERIFY_INTEGRAL_COMMAND(raw"\frac{x^3}{3}", "x^2", "x")
    @test occursin("verify_integral", cmd)
    @test VERIFY_INTEGRAL(raw"\frac{x^3}{3}", "x^2", "x") == "0"
    answer, first_time, warm_time = time_call(() -> INTEGRATE_TEXT("x^2", "x", FPARAMS); repeats=1, answer_boundary=true)
    @test isfinite(first_time) && isfinite(warm_time)
    status, note = check_integral(answer, "x^2", ""; certified="x^3/3", complex_point=FCOMPLEX_POINT)
    @test status == :verified_numeric
    @test occursin("complex x=", note)
    @test occursin("certified: agree", note)
end
