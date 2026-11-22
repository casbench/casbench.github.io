using Test
include(joinpath(@__DIR__, "..", "lib", "poly.jl"))
include(joinpath(@__DIR__, "..", "J_rur", "check.jl"))
q(x) = BigInt(x)//BigInt(1)
polys = ["x^2-1", "y-x"]
vars = ["x", "y"]
good = (vars=vars, linear_form=String[], elim=q.([-1,0,1]), denom=q.([1]),
        param=[q.([0,1])], solutions=[q.([1,1]), q.([-1,-1])])
@testset "RUR substitution and lifting" begin
    @test first(check_rur(good, polys, vars)) == :verified_numeric
    @test first(check_rur(merge(good, (param=[q.([1,1])],)), polys, vars)) == :wrong
    @test first(check_rur(merge(good, (solutions=[q.([2,1])],)), polys, vars)) == :wrong
    @test first(check_rur(merge(good, (solutions=Vector{Vector{Rational{BigInt}}}(),)), polys, vars)) == :unverified
    @test first(check_rur(merge(good, (denom=q.([-1,1]),)), polys, vars)) == :unverified
end
