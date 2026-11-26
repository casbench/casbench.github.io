# The numeric check evaluates the integrand in Julia's complex arithmetic. Until 2026-11-26 two things made that
# value a matter of convention rather than of the integrand:
# - a zero imaginary part could be negative (cos(2.53 + 0.0im) is -0.819 - 0.0im, -(1.7 + 0.0im) is -1.7 - 0.0im), which
#   put a power or a root of a negative real on the other side of its cut: sqrt(-a) gave -1.30im, not the principal
#   +1.30im that every system gives;
# - a real check point could lie on a branch cut of the integrand (bench F case 348: cos(c+d x) and a + a sec(c+d x) are
#   negative reals on all of [0.21, 0.83]), where the value is only a convention: Giac's answer, right in the principal
#   convention, was graded wrong (F' = -f), and so were FriCAS's and Sage/Giac's.
# Zero imaginary parts are now made +0.0 at every operation, and a real point where the integrand differs on the two
# sides of the real axis is not used, as a pole is not. No system is started.
#
#   julia --project=envs/subprocess test/integration_cuts.jl
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
include(joinpath(@__DIR__, "..", "lib", "integration_check.jl"))

struct ValueAnswer
    text::String
    F::Function
end
Base.string(a::ValueAnswer) = a.text
EVAL(a::ValueAnswer, pt) = a.F(pt)

@testset "integrand values near branch cuts" begin
    f = Mapleish.make_evaluator("sqrt(-a)", [:x, :a])
    @test f(Dict(:x => 0.3, :a => 1.7)) ≈ im * sqrt(1.7)                         # the principal value
    g = Mapleish.make_evaluator("cos(c+d*x)^(3/2)", [:x, :c, :d])
    @test imag(g(Dict(:x => 0.21, :c => 2.3, :d => 1.1))) < 0                    # (-0.819)^(3/2) = -0.742im, principal
    # bench F case 348: every real point is on a cut of the integrand, so none is usable, whatever the answer
    st, note = check_integral(ValueAnswer("0", pt -> 0.0), "(a+a*sec(c+d*x))^(5/2)/cos(c+d*x)^(3/2)", "")
    @test st == :unverified
    @test occursin("branch cut", note)
    # off any cut the check is unchanged
    @test check_integral(ValueAnswer("x^3/3", pt -> pt[:x]^3 / 3), "x^2", "")[1] == :verified_numeric
    @test check_integral(ValueAnswer("x", pt -> pt[:x]), "x^2", "")[1] == :wrong
    @test check_integral(ValueAnswer("2/3*(x+a)^(3/2)", pt -> 2 / 3 * (pt[:x] + pt[:a])^1.5), "sqrt(x+a)", "")[1] == :verified_numeric
end
