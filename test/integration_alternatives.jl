# An answer given as a list of forms (FriCAS: one antiderivative per case of a parameter's sign) is checked form by
# form at the fixed parameters: verified when one form verifies, wrong when every form fails. No system is started.
#
#   julia --project=envs/subprocess test/integration_alternatives.jl
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
include(joinpath(@__DIR__, "..", "lib", "integration_check.jl"))

struct FormsAnswer
    text::String
    F::Function
    alternatives::Vector{FormsAnswer}
end
FormsAnswer(text, F) = FormsAnswer(text, F, FormsAnswer[])
Base.string(a::FormsAnswer) = a.text
EVAL(a::FormsAnswer, pt) = a.F(pt)

# ∫ 1/(a+b cos x) dx; FPARAMS has a = 1.7 > b = 0.6, so the arctan form is the one for these values
atanform = FormsAnswer("2/sqrt(a^2-b^2)*atan(sqrt((a-b)/(a+b))*tan(x/2))",
                       pt -> (a, b, x = pt[:a], pt[:b], pt[:x]; 2 / sqrt(a^2 - b^2) * atan(sqrt((a - b) / (a + b)) * tan(x / 2))))
wrongform = FormsAnswer("x", pt -> pt[:x])
@testset "list answers" begin
    st, note = check_integral(FormsAnswer("[x, atan]", pt -> nothing, [wrongform, atanform]), "1/(a+b*cos(x))", "")
    @test st == :verified_numeric
    @test occursin("form 2 of the 2", note)
    st, note = check_integral(FormsAnswer("[x, x]", pt -> nothing, [wrongform, wrongform]), "1/(a+b*cos(x))", "")
    @test st == :wrong
    @test check_integral(atanform, "1/(a+b*cos(x))", "")[1] == :verified_numeric        # a single answer as before
    @test check_integral(FormsAnswer("[x]", pt -> nothing, [wrongform]), "1/(a+b*cos(x))", "")[1] == :unverified   # one form: not a list
end
