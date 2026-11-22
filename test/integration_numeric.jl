using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
EVAL(f::Function, point) = f(point[:x])
include(joinpath(@__DIR__, "..", "lib", "integration_check.jl"))
include(joinpath(@__DIR__, "..", "lib", "verify_expr.jl"))

@testset "integration numeric check" begin
    status, note = check_integral(x -> x^3/3, "x^2", ""; certified="x^3/3")
    @test status == :verified_numeric
    @test occursin("Float64 x:Fprime/f=", note)
    @test all(occursin(string(x) * ":", note) for x in FPOINTS)
    @test occursin("certified: agree", note)
    @test check_integral(x -> x^2, "x^2", "")[1] == :wrong
    @test check_integral(x -> x^3/3 + im*x, "x^2", "")[1] == :wrong
    @test check_integral(x -> nothing, "x^2", "")[1] == :unverified
    @test check_integral(x -> x^3/3, "x^2", ""; certified="x^2")[2] |> x -> occursin("certified: differ", x)
    @test entire_integrand("x^2+sin(x)")
    @test !entire_integrand("1/x")
    @test !entire_integrand("sqrt(x)")
    @test analytic_complex_sample("1/x")
    @test analytic_complex_sample("sqrt(x) + log(x) + tan(x)")
    @test analytic_complex_sample("(a+x)^(-2)", FPARAMS)
    @test !analytic_complex_sample("log(-1)")
    @test !analytic_complex_sample("sqrt(-1)")
    @test !analytic_complex_sample("erf(x)")
    @test !analytic_complex_sample("1/(x-(0.57+0.125*I))")
    @test !analytic_complex_sample("(-1)^(x-x+2)")
    @test analytic_complex_sample("(-1)^2")
    @test !analytic_complex_sample("1/(x-a)", Dict(:a => 0.57+0.125im))
    @test complex_sample_enabled("1/x", FPARAMS)
    BenchCommon.COMPLEX_SAMPLE_ENABLED[] = false
    @test !complex_sample_enabled("1/x", FPARAMS)
    BenchCommon.COMPLEX_SAMPLE_ENABLED[] = nothing
    st, note = check_integral(log, "1/x", ""; complex_point=FCOMPLEX_POINT)
    @test st == :verified_numeric && occursin("complex x=", note)
    st, note = check_integral(x -> x^3/3, "x^2", ""; complex_point=FCOMPLEX_POINT)
    @test st == :verified_numeric && occursin("complex x=", note)
    @test check_integral(x -> real(x)^3/3, "x^2", ""; complex_point=FCOMPLEX_POINT)[1] == :unverified
    @test check_integral(x -> x isa Real ? x^3/3 : nothing, "x^2", ""; complex_point=FCOMPLEX_POINT)[1] == :unverified
    real_only = check_integral(x -> log(abs(x)), "1/x", "log(x)"; certified="log(x)", complex_point=FCOMPLEX_POINT)
    @test real_only[1] == :unverified
    @test occursin("certified: agree", real_only[2])
    @test occursin("grade=ungraded", real_only[2])
end

@testset "exact verifier reconstruction" begin
    expr = exact_verify_expr("(1/3)*x^3")
    @test Core.eval(Main, :(let x=3; $expr; end)) == 9
    @test_throws ErrorException exact_verify_expr("0.3333333333333333*x")
    @test_throws ErrorException exact_verify_expr("begin x; x end")
end
