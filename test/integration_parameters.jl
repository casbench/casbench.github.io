# Every free symbol of a bench F or bench H integrand has a fixed value in the
# parameters its check (and the adapters) use; otherwise a correct answer can
# only be unverified, and a system that needs declared symbols (Sage) raises
# instead of answering. Also pins the number of bench H problems, so that a
# change of the candidate value sets cannot silently shift the case indices.
#
#   julia --project=envs/subprocess test/integration_parameters.jl
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
include(joinpath(@__DIR__, "..", "H_osr", "problems.jl"))      # also includes lib/integration_check.jl

const CONSTANTS = ("x", "Pi", "pi", "I", "E")
free_symbols(s) = unique(m.match for m in eachmatch(r"\b[A-Za-z_][A-Za-z_0-9]*\b", s)
                         if !occursin(Regex("\\b" * m.match * "\\s*\\("), s) && !(m.match in CONSTANTS))

@testset "bench H: every integrand symbol has a value" begin
    @test length(PROBLEMS) == 641
    for p in PROBLEMS
        integrand, _, params = p.args(Dict{Symbol,Any}())
        missing_symbols = [s for s in free_symbols(integrand) if !haskey(params, Symbol(s))]
        @test isempty(missing_symbols) || (@info "symbols without a value" p.name missing_symbols; false)
    end
    r9 = only(p for p in PROBLEMS if startswith(p.name, "integration.rubi_3_2_3_r9 "))
    @test r9.args(Dict{Symbol,Any}())[3][:t] == 0.75
end

@testset "bench F: every integrand symbol has a value" begin
    for line in Iterators.drop(eachline(joinpath(@__DIR__, "..", "F_integration", "sample.tsv")), 1)
        f = split(line, '\t')
        missing_symbols = [s for s in free_symbols(f[4]) if !haskey(FPARAMS, Symbol(s))]
        @test isempty(missing_symbols) || (@info "symbols without a value" f[1] missing_symbols; false)
    end
end
