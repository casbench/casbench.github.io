# Small real-adapter check: a polynomial is entire, so its antiderivative must
# be evaluable at the documented complex point as well as the real points.
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
system = only(ARGS)
system in ("giac", "sympy", "symj", "symbolics", "maxima", "fricas", "sage_giac", "sage_maxima", "sage_fricas", "sage_sympy") || error("unknown adapter")
include(joinpath(@__DIR__, "..", "lib", "adapters", system * ".jl"))
include(joinpath(@__DIR__, "..", "lib", "integration_check.jl"))
include(joinpath(@__DIR__, "..", "lib", "verify_expr.jl"))
@testset "integration and self-check: $system" begin
    F = INTEGRATE_TEXT("x^2", "x", FPARAMS)
    if system in ("maxima", "fricas", "sage_giac", "sage_maxima", "sage_fricas", "sage_sympy")
        @test hasfield(typeof(F), :answer_ns) && F.answer_ns > 0
    end
    status, note = check_integral(F, "x^2", ""; certified="x^3/3", complex_point=FCOMPLEX_POINT)
    @test status == :verified_numeric
    @test occursin("complex x=", note)
    @test occursin("certified: agree", note)
    answer = string(F)
    @test VERIFY_INTEGRAL(answer, "x^2", "x") == "0"
    @test VERIFY_INTEGRAL("(1/6)*x^2", "x/3", "x") == "0"
    @test occursin(system in ("fricas", "sage_fricas") ? "d(" : "diff", lowercase(VERIFY_INTEGRAL_COMMAND(answer, "x^2", "x")))
    # 1/x is analytic at the complex sample despite having a pole at zero.
    rational = INTEGRATE_TEXT("1/x", "x", FPARAMS)
    st, rational_note = check_integral(rational, "1/x", ""; complex_point=FCOMPLEX_POINT)
    if occursin("abs(", lowercase(string(rational)))
        @test st == :unverified
        @test occursin("non-holomorphic", rational_note)
    else
        @test st == :verified_numeric
        @test occursin("complex x=", rational_note)
    end
end
