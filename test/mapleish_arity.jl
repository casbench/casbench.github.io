# Maple's multi-argument Zeta(0, s, a) (Hurwitz zeta) and Ei(n, z) (generalized exponential integral E_n) are
# translated by arity, with explicit "no translation" errors where a system lacks the function, and the plain-Julia
# check evaluates them (references from mpmath). No system is started.
#
#   julia --project=envs/subprocess test/mapleish_arity.jl
using Test
include(joinpath(@__DIR__, "..", "lib", "mapleish.jl"))
using .Mapleish

@testset "Zeta and Ei by arity" begin
    @test translate("x*Zeta(0,2,a+b*x)", :sympy) == "x*zeta(2,a+b*x)"
    @test translate("x*Zeta(0,2,a+b*x)", :sage) == "x*hurwitz_zeta(2,a+b*x)"
    @test translate("x*Zeta(0,2,a+b*x)", :julia) == "x*zeta(2,a+b*x)"
    for d in (:giac, :maxima, :fricas)
        @test_throws ErrorException translate("x*Zeta(0,2,a+b*x)", d)
    end
    @test_throws ErrorException translate("Zeta(1,2,x)", :sympy)            # the derivative in s: not translated
    @test translate("Ei(2,b*x)/x", :sympy) == "expint(2,b*x)/x"
    @test translate("Ei(2,b*x)/x", :sage) == "exp_integral_e(2,b*x)/x"
    @test translate("Ei(2,b*x)/x", :maxima) == "expintegral_e(2,b*x)/x"
    @test translate("Ei(2,b*x)/x", :giac) == "Ei(b*x,2)/x"                  # Giac's E_n takes z first
    @test translate("Ei(n,a+b*x)/(c+d*x)", :julia) == "expint(n,a+b*x)/(c+d*x)"
    @test_throws ErrorException translate("Ei(2,b*x)/x", :fricas)
    # the one-argument forms are unchanged
    @test translate("Ei(a+b*x)^2", :julia) == "expinti(a+b*x)^2"
    @test translate("Ei(a+b*x)^2", :maxima) == "expintegral_ei(a+b*x)^2"
    @test translate("Zeta(3)", :sympy) == "zeta(3)"
    @test translate("Ei(2,Ei(x))", :sympy) == "expint(2,Ei(x))"            # nested
    # the Julia check evaluates them (mpmath: zeta(2,1.7), E_2(0.6), E_1.5(2.3))
    names = [:x, :a, :n]
    @test real(make_evaluator("Zeta(0,2,a)", names)(Dict(:x => 0.0, :a => 1.7, :n => 0.0))) ≈ 0.793232830163998 rtol = 1e-12
    @test real(make_evaluator("Ei(2,x)", names)(Dict(:x => 0.6, :a => 0.0, :n => 0.0))) ≈ 0.276183934180385 rtol = 1e-12
    @test real(make_evaluator("Ei(n,x)", names)(Dict(:x => 2.3, :a => 0.0, :n => 1.5))) ≈ 0.0286326555573764 rtol = 1e-10
end
