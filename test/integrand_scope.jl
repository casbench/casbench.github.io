# The integrand of benches F and H is built for Symbolics.jl and SymJ.jl by evaluating its Julia translation. Until
# 2026-11-28 that evaluation ran in Main, where the special functions of the translation (expint, expinti, sinint,
# cosint, sinhint, coshint, gamma with two arguments, zeta) are not defined: the case was an UndefVarError of the
# adapter, and the system never received it (20 F cases for Symbolics.jl, 24 for SymJ.jl). The evaluation now sees
# SpecialFunctions (and RischIntegrate's Shi and Chi); what a system cannot integrate is its own answer or error.
#
#   julia --project=envs/symbolics test/integrand_scope.jl symbolics
#   julia --project=envs/symj test/integrand_scope.jl symj
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
system = only(ARGS)
system in ("symbolics", "symj") || error("unknown adapter")
include(joinpath(@__DIR__, "..", "lib", "adapters", system * ".jl"))
@testset "special functions reach $system" begin
    for integrand in ("Ei(x)/x", "Si(x)", "x*Ci(x)", "Shi(x)", "Chi(x)/x", "GAMMA(2,x)", "erf(x)")
        out = try INTEGRATE_TEXT(integrand, "x") catch err; err end
        @test !(out isa UndefVarError)
    end
end
