# The Sage adapter recognises an unevaluated integral in both forms Sage
# prints: integrate(...) from its own front end and integral(...) from FriCAS.
# No Sage process is started.
#
#   julia --project=envs/subprocess test/sage_unsolved.jl
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
const SAGE_ALGORITHM = "fricas"
include(joinpath(@__DIR__, "..", "lib", "adapters", "sage.jl"))

answer(text) = SageAnswer(text, Dict{ComplexF64,ComplexF64}(), NaN, UInt64(0))
@testset "Sage unevaluated integrals are unsolved" begin
    @test UNSOLVED(:integrate_text, answer("integral(x^m*cos(1/2*b*x^n + a)^2, x)"))
    @test UNSOLVED(:integrate_text, answer("-1/6*x + integral(1/(b*x*e^(d*x + c) + a*x), x)"))
    @test UNSOLVED(:integrate_text, answer("integrate(x^m*cos(x), x)"))
    @test UNSOLVED(:integrate_text, answer("sage_error: NotImplementedError: integral not implemented"))
    @test !UNSOLVED(:integrate_text, answer("1/3*x^3"))
    @test !UNSOLVED(:integrate_text, answer("integrality_check(x)"))
end
