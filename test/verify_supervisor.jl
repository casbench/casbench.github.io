using Test
include(joinpath(@__DIR__, "..", "lib", "supervise.jl"))

@testset "supervised verification preserves answer" begin
    mktempdir() do dir
        worker = joinpath(@__DIR__, "fake_integral_worker.jl")
        verifier = joinpath(@__DIR__, "fake_integral_verifier.jl")
        for (mode, enabled, worker_crash, expected) in (("pass", "1", "0", "verified_symbolic"),
                                                        ("unsolved", "1", "0", "verify_unsolved"),
                                                        ("timeout", "1", "0", "verify_timeout"),
                                                        ("crash", "1", "0", "verify_unsolved"),
                                                        ("pass", "0", "0", ""),
                                                        ("pass", "1", "1", "verified_symbolic"))
            out = joinpath(dir, mode * enabled * worker_crash * ".tsv")
            withenv("BENCH_VERIFY_INTEGRALS" => enabled, "BENCH_VERIFY_WORKER" => verifier,
                    "BENCH_VERIFY_TIMEOUT" => (mode == "timeout" ? "0.3" : "5"), "BENCH_VERIFY_STARTUP_TIMEOUT" => "30",
                    "BENCH_FAKE_VERIFY_MODE" => mode, "BENCH_FAKE_WORKER_CRASH" => worker_crash,
                    "BENCH_RESUME" => "0") do
                supervise(@__DIR__, worker, "F_integration", "mock", out, 10.0, String[])
            end
            rows = read_records(out)
            @test length(rows) == 1
            r = only(rows)
            @test (r.status, r.t_first, r.t_warm) == ("verified_numeric", 1.25, 0.5)
            @test r.verify_status == expected
            if enabled == "1"
                @test r.verify_input == "simplify(diff(x^2/2,x)-x)"
                @test expected == "verify_timeout" ? r.verify_time >= 0.3 : expected == "verify_unsolved" && mode == "crash" ? isnan(r.verify_time) : r.verify_time == 0.125
            else
                @test isnan(r.verify_time)
            end
        end
        numeric_out = joinpath(dir, "numeric.tsv")
        withenv("BENCH_FAKE_NUMERIC_HANG" => "1", "BENCH_NUMERIC_VERIFY_TIMEOUT" => "0.3",
                "BENCH_VERIFY_INTEGRALS" => "0", "BENCH_RESUME" => "0") do
            supervise(@__DIR__, worker, "F_integration", "mock", numeric_out, 10.0, String[])
        end
        numeric = only(read_records(numeric_out))
        @test (numeric.status, numeric.t_first, numeric.result) == ("unverified", 1.25, "x^2/2")
        @test isempty(numeric.verify_status)
        @test !isfile(numeric_out * ".numeric-request")
        # A stale response from a previous interrupted run must not be
        # attached to the answer produced on resume.
        resumed = joinpath(dir, "resumed.tsv")
        append_record(resumed, Record("F_integration", "mock", 0, "_load", "using", "verified", 1.0, NaN, "", ""))
        open(io -> serialize(io, (status="verified_symbolic", time=0.01, command="stale")), resumed * ".verify-response", "w")
        withenv("BENCH_VERIFY_INTEGRALS" => "1", "BENCH_VERIFY_WORKER" => verifier,
                "BENCH_VERIFY_TIMEOUT" => "5", "BENCH_FAKE_VERIFY_MODE" => "unsolved",
                "BENCH_FAKE_WORKER_CRASH" => "0", "BENCH_RESUME" => "1") do
            supervise(@__DIR__, worker, "F_integration", "mock", resumed, 10.0, String[])
        end
        fresh = last(read_records(resumed))
        @test fresh.verify_status == "verify_unsolved"
        @test fresh.verify_input == "simplify(diff(x^2/2,x)-x)"

        legacy = joinpath(dir, "legacy.tsv")
        write(legacy, join(split(HEADER, '\t')[1:15], '\t') * "\n")
        original = read(legacy, String)
        withenv("BENCH_RESUME" => "1") do
            @test_throws ErrorException supervise(@__DIR__, worker, "F_integration", "mock", legacy, 10.0, String[])
        end
        @test read(legacy, String) == original
    end
end
