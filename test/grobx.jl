using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
include(joinpath(@__DIR__, "..", "lib", "adapters", "grobx.jl"))
include(joinpath(@__DIR__, "..", "G_groebner", "problems.jl"))
include(joinpath(@__DIR__, "..", "G_groebner", "systems.jl"))

@testset "GrobX Q and finite fields" begin
    @test GROBX_VERSION == "0.73.3"
    @test "grobx" in selected_g_systems("")
    @test selected_g_systems("grobx") == ["grobx"]
    @test_throws ErrorException selected_g_systems("grobx,missing")
    @test_throws ErrorException selected_g_systems("grobx,grobx")
    vars = ["x", "y"]
    polys = ["x^2+y", "x*y-1"]
    for p in (0, PRIME)
        empty!(INPUT_LOG)
        basis = GROEBNER(polys, vars, p)
        st, note = check_gb(basis, polys, vars, p)
        @test st == :verified
        @test occursin("sha=", note)
        @test isfinite(basis.elapsed) && basis.elapsed >= 0
        @test basis.process_peak_rss_kib > 0
        @test occursin("threads=1, seed=0", only(INPUT_LOG))
        @test occursin("\n$(p)\n", only(INPUT_LOG))
    end
    # Henrion contains rational coefficients and must be reduced mod p.
    f = "24//5*x + 3//5*y - 2"
    g = grobx_modp_string(f, vars, PRIME)
    @test Poly.tofield(Poly.parse_poly(f, vars), PRIME) == Poly.tofield(Poly.parse_poly(g, vars), PRIME)
    rational_system = ["x+1//2*y", "y-1"]
    for p in (0, PRIME)
        basis = GROEBNER(rational_system, vars, p)
        @test first(check_gb(basis, rational_system, vars, p)) == :verified
    end
end

@testset "GrobX supervised base cases" begin
    root = normpath(joinpath(@__DIR__, ".."))
    mktempdir() do dir
        out = joinpath(dir, "G_groebner_grobx.tsv")
        withenv("BENCH_STOP" => "2", "BENCH_RESUME" => "0", "BENCH_G_HARD" => "0") do
            run(`$(Base.julia_cmd()) --startup-file=no $(joinpath(root, "lib", "supervise.jl")) $(joinpath(root, "envs", "subprocess")) $(joinpath(root, "lib", "worker.jl")) G_groebner grobx $out 90`)
        end
        rows = filter(r -> r.idx > 0, read_records(out))
        @test length(rows) == 2
        @test all(r -> r.status == "verified", rows)
        @test all(r -> occursin("threads=1, seed=0", r.input), rows)
        @test all(r -> occursin("process_peak_rss_kib=", r.note), rows)
        @test all(r -> occursin("check_wall_s=", r.note), rows)
        @test all(r -> occursin("terms=", r.note) && occursin("sha=", r.note), rows)
    end
end
