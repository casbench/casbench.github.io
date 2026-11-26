using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon

@testset "verification record compatibility" begin
    mktempdir() do dir
        path = joinpath(dir, "new.tsv")
        command = "α = 1\n\tF = \\frac{x}{2}\r\n" * repeat("x", 2500)
        r = Record("F_integration", "Example", 1, "case", "integrate_text", "verified_numeric",
                   1.25, 0.5, "F\n" * repeat("y", 1200), "numeric\n" * repeat("z", 500), "integrate(f,x)\n\tπ", 0.5, "0.5", 0.2, "run",
                   "verify_timeout", 60.0, command)
        append_record(path, r)
        back = only(read_records(path))
        @test (back.t_first, back.t_warm, back.verify_status, back.verify_time) == (1.25, 0.5, "verify_timeout", 60.0)
        @test back.verify_input == command
        @test back.result == "F\n" * repeat("y", 1200)
        @test back.input == "integrate(f,x)\n\tπ"
        @test back.note == "numeric\n" * repeat("z", 500)
        @test split(first(readlines(path)), '\t')[16:18] == ["verify_status", "verify_time_s", "verify_input"]
        append_record(path, Record("F", "Example", 2, "case", "op", "error", NaN, NaN, "", ""))
        @test length(read_records(path)) == 2

        legacy = joinpath(dir, "legacy.tsv")
        header = join(split(HEADER, '\t')[1:15], '\t')
        line = join(("F", "Example", "3", "old", "op", "verified", "1", "0.5", "F", "", "in", "0.5", "0.5", "0.2", "oldrun"), '\t')
        write(legacy, header * "\n" * line * "\n")
        old = only(read_records(legacy))
        @test old.verify_status == "" && isnan(old.verify_time) && old.verify_input == ""
        original = read(legacy, String)
        @test_throws ErrorException append_record(legacy, r)
        @test read(legacy, String) == original

        modern17 = joinpath(dir, "17.tsv")
        write(modern17, header * "\tverify_status\tverify_time_s\n" * line * "\tverified_symbolic\t4.2\n")
        rr = only(read_records(modern17))
        @test (rr.verify_status, rr.verify_time, rr.verify_input) == ("verified_symbolic", 4.2, "")
    end
end

struct TimedAnswer
    answer_ns::UInt64
end
function slow_post_answer()
    sleep(0.05)
    stamp = time_ns()
    sleep(0.35)  # stands for numeric evaluation after the answer is emitted
    TimedAnswer(stamp)
end
@testset "answer timing excludes subsequent numeric checks" begin
    repeats = Float64[]
    start = time_ns()
    _, first_time, warm_time = time_call(slow_post_answer; repeats=1, times=repeats, answer_boundary=true)
    total = (time_ns() - start) / 1e9
    @test total > 0.7
    @test 0.04 <= first_time < 0.3
    @test 0.04 <= warm_time < 0.3
    @test length(repeats) == 1 && repeats[1] == warm_time
end

@testset "input checkpoint does not enter timing" begin
    f = () -> (log_input!("a long command"); 1)
    time_call(f; repeats=0) # compile before testing the timing boundary
    empty!(INPUT_LOG)
    BenchCommon.INPUT_CHECKPOINT[] = () -> sleep(0.1)
    try
        _, first, _ = time_call(f; repeats=0)
        @test first < 0.08
        @test INPUT_LOG == ["a long command"]
    finally
        BenchCommon.INPUT_CHECKPOINT[] = nothing
    end
end

@testset "first answer checkpoint is outside measured time" begin
    f = () -> 42
    time_call(f; repeats=0)
    saved = Ref(false)
    _, first, warm = time_call(f; repeats=1, after_first=(answer, elapsed) -> begin
        saved[] = answer == 42 && isfinite(elapsed)
        sleep(0.1)
    end)
    @test saved[]
    @test first < 0.08 && warm < 0.08
end

@testset "machine block names the host by BENCH_HOST, not by the hostname" begin
    mktempdir() do dir
        path = joinpath(dir, "machine.txt")
        saved = BenchCommon.RUN_ID[]
        BenchCommon.RUN_ID[] = ""          # the run id of a fresh process, generated under BENCH_HOST
        try
            withenv("BENCH_HOST" => "host-test", "BENCH_RUN_ID" => nothing) do
                write_machine_info(path, Pair{String,String}[]; calibration = false)
            end
        finally
            BenchCommon.RUN_ID[] = saved
        end
        fields = Dict(split(l, '\t'; limit = 2) for l in readlines(path) if occursin('\t', l))
        @test fields["host"] == "host-test"
        @test fields["host_slug"] == "host-test"
        @test !occursin(gethostname(), read(path, String)) || gethostname() == "host-test"
    end
end
