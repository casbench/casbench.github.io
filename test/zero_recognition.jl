using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
struct Residual end
Base.show(io::IO, ::Residual) = print(io, "sqrt(2)^2 - 2")
EVAL(::Residual, at) = 0.0
EVAL(::Any, at) = nothing
struct TestHP
    text::String
    value::BigFloat
end
Base.show(io::IO, o::TestHP) = print(io, o.text)
EVAL_HIGH_PRECISION(o::TestHP, digits::Int, at) = o.value
EVAL_HIGH_PRECISION(o::Integer, digits::Int, at) = BigFloat(o)
EVAL_HIGH_PRECISION(o, digits::Int, at) = nothing
const SYSTEM_KEY = "test"
const OPS = Dict{Symbol,Any}()
mktempdir() do dir
    cp(joinpath(@__DIR__, "..", "E_suite", "problems.jl"), joinpath(dir, "problems.jl"))
    cp(joinpath(@__DIR__, "..", "E_suite", "zero_reference.jl"), joinpath(dir, "zero_reference.jl"))
    write(joinpath(dir, "tasks_test.jl"), "const TASKS = Dict{String,Any}()\n")
    include(joinpath(dir, "problems.jl"))
end
@testset "identity zero cases" begin
    for name in ("A nested radical", "The Pythagorean identity", "A removable singularity", "The golden cosine", "tan(pi/12)",
                 "An exponential of a logarithm")
        p = only(filter(p -> p.name == name, PROBLEMS))
        @test p.check(0)[1] == :verified_numeric
        @test occursin("numeric evaluation", p.check(0)[2])
    end
    for system in ("giac", "sympy", "symj", "symbolics")
        path = joinpath(@__DIR__, "..", "E_suite", "tasks_$(system).jl")
        @test Meta.parseall(read(path, String)) isa Expr
    end
end

@testset "near-integer reference is enclosed and nonzero" begin
    lo, hi = hardy_reference_interval()
    @test lo < hi < 0
    @test lo > -big"1e-12"
    @test hi - lo < big"1e-50"
    lo2, hi2 = hardy_reference_interval(bits = 384)
    @test lo <= lo2 < hi2 <= hi
end

@testset "high-precision nonzero controls" begin
    @test check_identity_high_precision(0, :zero)[1] == :verified_numeric
    @test check_identity_high_precision("0", :zero)[1] == :verified_numeric
    @test check_identity_high_precision("1/1000000000000000000000000000000", :rational)[1] == :verified_numeric
    @test check_identity_high_precision("0.0", :zero)[1] == :unverified
    @test check_identity_high_precision(0, :hardy)[1] == :wrong
    @test check_identity_high_precision(0, :rational)[1] == :wrong
    lo, hi = hardy_reference_interval()
    @test check_identity_high_precision(TestHP("answer", (lo + hi) / 2), :hardy)[1] == :verified_numeric
    @test check_identity_high_precision(TestHP("answer", big(0)), :hardy)[1] == :wrong
    lo, hi = rational_control_interval()
    @test check_identity_high_precision(TestHP("answer", (lo + hi) / 2), :rational)[1] == :verified_numeric
    @test check_identity_high_precision("answer", :zero)[1] == :unverified
    @test check_identity_high_precision(TestHP("unevaluated", big(0)), :zero)[1] == :unsolved
    @test check_identity_high_precision(TestHP("unevaluated", big"1e-70"), :zero)[1] == :unsolved
    @test check_identity_high_precision(TestHP("incorrect", big"1e-10"), :zero)[1] == :wrong
end
