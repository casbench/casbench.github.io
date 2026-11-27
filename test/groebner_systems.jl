# The input files of benches G and J are what tools/groebner/systems.jl writes from the definitions of the systems
# (Katsura, cyclic-n, eco, noon, Henrion, Chandrasekhar). Plain Julia, no package.
using Test
include(joinpath(@__DIR__, "..", "tools", "groebner", "systems.jl"))
@testset "bench G systems from their definitions" begin
    @test read(joinpath(@__DIR__, "..", "G_groebner", "inputs.jl"), String) == inputs_text()
    @test read(joinpath(@__DIR__, "..", "G_groebner", "hard_inputs.jl"), String) == hard_inputs_text()
end
