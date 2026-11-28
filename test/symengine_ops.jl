# The operations of bench D receive the same arguments for every adapter: (f, x, order) for a series and the rows of a
# matrix for a determinant. The SymEngine.jl adapter took (f, x, x0, n) and indexed the rows as a matrix: both cases
# were a MethodError of the adapter, not of SymEngine, on both hosts.
#
#   julia --project=envs/symengine test/symengine_ops.jl
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
include(joinpath(@__DIR__, "..", "lib", "adapters", "symengine.jl"))
include(joinpath(@__DIR__, "..", "D_coverage", "problems.jl"))
@testset "SymEngine.jl in bench D" begin
    for name in ("series exp(x) order 6", "det [[a,b],[c,x]]")
        prob = only(filter(p -> p.name == name, PROBLEMS))
        out = OPS[prob.op](prob.args(VAR)...)
        @test prob.check(out) in (:verified, :verified_numeric)
    end
end
