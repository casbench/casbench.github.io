# The FriCAS scripts bind the integrand, the answer and the check results to names; a name that is also a parameter
# of the integrand replaces that parameter in everything evaluated after it. Until 2026-11-26 the integrand was bound
# to `f`: every case with the parameter f lost its numeric check (`eval(resf, [f = 1.3, ...])` substituted the
# integrand's value, "Cannot compute the numerical value of a non-constant expression"), and the symbolic check read
# the answer with f replaced by the integrand. No assigned name may be a parameter name.
#
# Runs without FriCAS: the scripts are read back from the input log (`true` stands for FriCAS and gives no answer).
using Test
ENV["FRICAS"] = "true"
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
include(joinpath(@__DIR__, "..", "lib", "adapters", "fricas.jl"))
include(joinpath(@__DIR__, "..", "lib", "integration_check.jl"))

assigned(script) = [m[1] for m in eachmatch(r"(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*(?::[^=\n]*)?:=", script)]
params = Set(string.(union(keys(FPARAMS), (:t,))))       # bench F's values and bench H's extra symbol

@testset "FriCAS script names" begin
    empty!(INPUT_LOG)
    @test_throws ErrorException INTEGRATE_TEXT("sin(f*x)+F*r*x", "x", FPARAMS)
    script = join(INPUT_LOG, "\n")
    names = assigned(script)
    @test !isempty(names)
    @test isempty(intersect(Set(names), params))
    names = assigned(VERIFY_INTEGRAL_COMMAND("((-1)*cos(f*x))/f+F*r*x^2/2", "sin(f*x)+F*r*x", "x"))
    @test !isempty(names)
    @test isempty(intersect(Set(names), params))
end
