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
    empty_solutions = Vector{Vector{Rational{BigInt}}}()
    @test first(check_rur(merge(good, (solutions=empty_solutions,)), polys, vars)) == :unverified
    no_real = merge(good, (elim=q.([1,0,1]), solutions=empty_solutions))
    @test first(check_rur(no_real, ["x-y", "y^2+1"], vars)) == :verified_numeric
    @test first(check_rur(merge(good, (denom=q.([-1,1]),)), polys, vars)) == :unverified
    complex_example = (vars=vars, linear_form=String[], elim=q.([-1,0,0,1]), denom=q.([1]),
                       param=[q.([0,1])], solutions=[q.([1,1])])
    status, note = check_rur(complex_example, ["x-y", "y^3-1"], vars)
    @test status == :verified_numeric
    @test occursin("3 independently approximated complex roots", note)
    roots = complex_roots(q.([1,0,1]))
    @test roots !== nothing && length(roots) == 2 && all(abs(z*z+1) < big"1e-30" for z in roots)
    @test complex_roots(q.([1,-2,1])) === nothing
    permuted = merge(good, (vars=["y", "x"],))
    @test first(check_rur(permuted, polys, vars)) == :verified_numeric
    aux = (vars=["x", "y", "A"], linear_form=["1", "2", "1"],
           elim=q.([-9,0,1]), denom=q.([1]),
           param=[[q(0), q(-1)/q(3)], [q(0), q(-1)/q(3)]],
           solutions=[q.([1,1]), q.([-1,-1])])
    @test first(check_rur(aux, polys, vars)) == :verified_numeric
    @test first(check_rur(merge(aux, (linear_form=["1", "3", "1"],)), polys, vars)) == :unverified
end
