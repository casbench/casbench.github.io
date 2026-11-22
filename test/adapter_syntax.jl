using Test

function parse_errors(ex)
    ex isa Expr || return false
    ex.head in (:error, :incomplete) || any(parse_errors, ex.args)
end

@testset "integration adapter sources parse" begin
    for name in ("giac", "sympy", "symj", "symbolics", "maxima", "fricas", "sage", "computeengine")
        path = joinpath(@__DIR__, "..", "lib", "adapters", name * ".jl")
        source = read(path, String)
        @test !parse_errors(Meta.parseall(source))
        @test occursin("OPS[:VERIFY_INTEGRAL]", source)
    end
end
