# Shared helpers for the benchmarks.
#
# Every bench writes one tab-separated line per (system, case) into
# benchmark/results/<bench>_<system>.tsv. The columns are fixed by HEADER below.
# Nothing here depends on any CAS package, so the file can be included from
# every environment.

module BenchCommon

using Dates
using Printf

export Record, HEADER, append_record, read_records, write_machine_info, INPUT_LOG, log_input!,
       time_call, truncate_str, clean, numeq, POINTS, POINTS_POS,
       run_id, host_slug, results_dir, git_info, loadavg, calibrate, with_verification,
       ANSWER_CALLBACK, TIME_CALL_START, notify_answer

const ROOT = normpath(joinpath(@__DIR__, ".."))

# ---------------------------------------------------------------------------
# Records
# ---------------------------------------------------------------------------

# status vocabulary (one of these strings in the `status` column):
#   verified     historical check passed, or an exact or symbolic check passed
#   verified_numeric  a numeric check passed
#   wrong        the system returned an answer and the check failed
#   unverified   an answer was returned but could not be evaluated numerically
#   unsolved     the system returned the problem unevaluated / incomplete
#   unavailable  the operation does not exist in this system
#   error        the call raised an exception (message in `note`)
#   timeout      the case exceeded the per-case time limit (killed by supervise.jl)
const STATUSES = ("verified", "verified_numeric", "wrong", "unverified", "unsolved", "unavailable", "error", "timeout")

struct Record
    bench::String
    system::String
    idx::Int
    case::String
    op::String
    status::String
    t_first::Float64   # seconds, first call in a fresh process (includes compilation)
    t_warm::Float64    # seconds, minimum over repeated calls (NaN if not measured)
    result::String     # textual result; new-format records preserve it in full
    note::String
    input::String      # full input in new-format records; older files may be truncated
    # the four columns below exist in files written from 2026-11-20 (harness with run identity):
    t_wall::Float64    # seconds, the harness's own wall time of the fastest measured call, whatever the system
                       # (for a system run as one process per case this includes the process start-up)
    repeats::String    # every repeated wall time in seconds, ";"-separated (the dispersion behind t_warm); "" if none
    load::Float64      # 1-minute load average of the machine just before the case (NaN if unknown)
    run::String        # run identifier: <date>_<host>[-dirty], the same in machine.txt (run_id)
    verify_status::String  # separate verification phase, empty when not run
    verify_time::Float64   # seconds spent in verification, never included in t_first/t_warm
    verify_input::String   # exact command sent to the verifier, when recorded
end
Record(bench, system, idx, case, op, status, t_first, t_warm, result, note, input, t_wall, repeats, load, run) =
    Record(bench, system, idx, case, op, status, t_first, t_warm, result, note, input, t_wall, repeats, load, run, "", NaN, "")
Record(bench, system, idx, case, op, status, t_first, t_warm, result, note) =
    Record(bench, system, idx, case, op, status, t_first, t_warm, result, note, "")
Record(bench, system, idx, case, op, status, t_first, t_warm, result, note, input) =
    Record(bench, system, idx, case, op, status, t_first, t_warm, result, note, input, NaN, "", NaN, run_id())

# Create a new immutable record without touching the measured answer times.
with_verification(r::Record, status, seconds, command) =
    Record(r.bench, r.system, r.idx, r.case, r.op, r.status, r.t_first, r.t_warm,
           r.result, r.note, r.input, r.t_wall, r.repeats, r.load, r.run, status, seconds, command)

const HEADER = "bench\tsystem\tidx\tcase\top\tstatus\tt_first_s\tt_warm_s\tresult\tnote\tinput\tt_wall_s\tt_repeats_s\tload_avg\trun\tverify_status\tverify_time_s\tverify_input"

# what the adapters send to their system during one case, in that system's syntax: the adapters call
# log_input! with every command, script or expression text; the worker clears it before each case and
# records it, so that a status can be checked against the exact input (a wrongly generated command is
# an error of the benchmark, not of the system)
# A subprocess adapter can announce its answer before it starts numeric
# evaluations. The worker uses this boundary to protect a completed answer
# if the later checking phase is interrupted.
const COMPLEX_SAMPLE_ENABLED = Ref{Union{Nothing,Bool}}(nothing)
const ANSWER_CALLBACK = Ref{Any}(nothing)
const TIME_CALL_START = Ref{UInt64}(0)
notify_answer(text, stamp) = ANSWER_CALLBACK[] === nothing ? nothing : ANSWER_CALLBACK[](String(text), stamp)

const INPUT_LOG = String[]
# An optional checkpoint protects a long-running case's exact command. The
# time spent writing it is subtracted from the answer timing.
const INPUT_CHECKPOINT = Ref{Any}(nothing)
const INPUT_CHECKPOINT_NS = Ref{UInt64}(0)
function log_input!(s)
    push!(INPUT_LOG, String(string(s)))
    if INPUT_CHECKPOINT[] !== nothing
        t0 = time_ns()
        try
            INPUT_CHECKPOINT[]()
        finally
            INPUT_CHECKPOINT_NS[] += time_ns() - t0
        end
    end
    nothing
end

clean(s) = replace(String(string(s)), '\t' => ' ', '\n' => ' ', '\r' => ' ')
# Verification commands can be multiline and must round-trip exactly in TSV.
escape_verify(s) = replace(String(s), "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n", "\r" => "\\r")
truncate_str(s, n = 200) = (s = clean(s); length(s) > n ? first(s, n) * "..." : s)

function append_record(path::AbstractString, r::Record)
    new = !isfile(path) || filesize(path) == 0
    # Appending new-width rows to a legacy file would silently corrupt it.
    # Keep historical files intact and require a new destination instead.
    if !new
        existing = open(readline, path)
        existing == HEADER || error("cannot append the new record format to historical results: $path")
    end
    open(path, "a") do io
        new && println(io, HEADER)
        println(io, join([r.bench, r.system, string(r.idx), clean(r.case), r.op, r.status,
                          @sprintf("%.6g", r.t_first), @sprintf("%.6g", r.t_warm),
                          escape_verify(r.result), escape_verify(r.note), escape_verify(r.input),
                          @sprintf("%.6g", r.t_wall), r.repeats, @sprintf("%.3g", r.load), r.run,
                          clean(r.verify_status), @sprintf("%.6g", r.verify_time), escape_verify(r.verify_input)], '\t'))
    end
end

function read_records(path::AbstractString)
    out = Record[]
    isfile(path) || return out
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        f = split(line, '\t'; keepempty = true)
        length(f) in (10, 11, 15, 17, 18) || continue
        push!(out, Record(f[1], f[2], parse(Int, f[3]), f[4], f[5], f[6],
                          parse(Float64, f[7]), parse(Float64, f[8]), length(f) >= 18 ? unescape_string(f[9]) : f[9], length(f) >= 18 ? unescape_string(f[10]) : f[10],
                          length(f) >= 18 ? unescape_string(f[11]) : length(f) >= 11 ? f[11] : "",
                          length(f) >= 15 ? parse(Float64, f[12]) : NaN, length(f) >= 15 ? f[13] : "",
                          length(f) >= 15 ? parse(Float64, f[14]) : NaN, length(f) >= 15 ? f[15] : "",
                          length(f) >= 17 ? f[16] : "", length(f) >= 17 && !isempty(f[17]) ? parse(Float64, f[17]) : NaN,
                          length(f) >= 18 ? unescape_string(f[18]) : ""))
    end
    out
end

# ---------------------------------------------------------------------------
# Timing
# ---------------------------------------------------------------------------

"""
    time_call(f; repeats=5, warm_budget=10.0, between=() -> nothing, times=Float64[])

Call `f()` once and record the wall-clock time of that first call (which, in a
fresh process, includes compilation). If it took less than `warm_budget`
seconds, call it `repeats` more times and record the minimum. `between` runs
before every repeated call (used to clear SymPy's cache). Returns
`(result, t_first, t_warm)`; `t_warm` is `NaN` when not measured. Every
repeated time is pushed to `times` (the dispersion behind the minimum).

Calls that take less than a millisecond are re-timed in a loop of `n` calls so
that the reported per-call time has microsecond resolution.
"""
function time_call(f; repeats = 5, warm_budget = 10.0, between = () -> nothing, times = Float64[], answer_boundary = false)
    t0 = time_ns()
    io0 = INPUT_CHECKPOINT_NS[]
    TIME_CALL_START[] = t0
    out = f()
    stamp(v) = answer_boundary && hasfield(typeof(v), :answer_ns) ? getfield(v, :answer_ns) : time_ns()
    end_first = stamp(out)
    t_first = end_first >= t0 ? (end_first - t0 - min(end_first - t0, INPUT_CHECKPOINT_NS[] - io0)) / 1e9 : NaN
    t_warm = NaN
    if t_first < warm_budget
        best = Inf
        for _ in 1:repeats
            between()
            if t_first < 1e-3 && !(answer_boundary && hasfield(typeof(out), :answer_ns))
                n = 200
                t0 = time_ns()
                io0 = INPUT_CHECKPOINT_NS[]
                for _ in 1:n
                    f()
                end
                elapsed = time_ns() - t0
                dt = (elapsed - min(elapsed, INPUT_CHECKPOINT_NS[] - io0)) / 1e9 / n
            else
                t0 = time_ns()
                io0 = INPUT_CHECKPOINT_NS[]
                value = f()
                finish = stamp(value)
                dt = finish >= t0 ? (finish - t0 - min(finish - t0, INPUT_CHECKPOINT_NS[] - io0)) / 1e9 : NaN
            end
            push!(times, dt)
            best = min(best, dt)
        end
        t_warm = best
    end
    return out, t_first, t_warm
end

# ---------------------------------------------------------------------------
# Numeric checks
# ---------------------------------------------------------------------------

# Fixed evaluation points shared by all benches. Values are "random looking"
# but constant, so every system is checked at the same points.
const POINTS = [Dict(:x => 0.37, :y => -1.21, :z => 0.83, :a => 1.7, :b => -0.6, :c => 2.3, :s => 1.9, :t => 0.45, :u => 0.9, :v => -1.4, :k => 2.0, :n => 3.0),
                Dict(:x => -1.53, :y => 0.44, :z => -0.27, :a => -0.8, :b => 1.9, :c => 0.35, :s => 2.6, :t => 1.2, :u => -0.3, :v => 0.7, :k => 3.0, :n => 4.0),
                Dict(:x => 2.11, :y => 1.05, :z => 1.61, :a => 0.55, :b => 0.9, :c => -1.2, :s => 3.3, :t => 0.8, :u => 1.8, :v => 2.2, :k => 5.0, :n => 6.0)]
# strictly positive points for log/sqrt domains
const POINTS_POS = [Dict(:x => 0.31, :y => 1.21, :z => 0.83, :t => 0.45, :s => 1.9),
                    Dict(:x => 0.57, :y => 0.44, :z => 0.27, :t => 1.2, :s => 2.6),
                    Dict(:x => 1.23, :y => 2.05, :z => 1.61, :t => 0.8, :s => 3.3)]

# plain numbers only: symbolic wrapper types (Num, Sym) are not accepted as values
isplainnumber(z) = z isa Union{AbstractFloat, Integer, Rational, AbstractIrrational} ||
    (z isa Complex && isplainnumber(real(z)))
numeq(a, b; rtol = 1e-8, atol = 1e-10) = isplainnumber(a) && isplainnumber(b) &&
    isfinite(abs(a)) && isfinite(abs(b)) && abs(a - b) <= atol + rtol * max(abs(a), abs(b))

# ---------------------------------------------------------------------------
# Run identity: which code produced a number, on which host, in which run
# ---------------------------------------------------------------------------

"""The name of the host in the results layout (`results/<host>/`): BENCH_HOST, else the hostname."""
host_slug() = replace(get(ENV, "BENCH_HOST", gethostname()), r"[^A-Za-z0-9._-]" => "-")

"""The results directory of this host: `results/<host>/` under the repository (created)."""
results_dir() = (d = joinpath(ROOT, "results", host_slug()); mkpath(d); d)

"""
    git_info() -> (commit, dirty, dirty_files, giac_jl, osr)

The commit of the harness, whether the working tree differs from it outside
`results/` (a run from a modified tree cannot be identified), the modified
files, and the commits of the Giac.jl and OSR submodules. Empty strings
outside a git checkout.
"""
function git_info()
    g(args...) = try strip(read(pipeline(ignorestatus(Cmd(`git $(collect(args))`; dir = ROOT)); stderr = devnull), String)) catch; "" end
    dirty = g("status", "--porcelain", "--untracked-files=no", "--", ".", ":!results")
    sub(dir) = isdir(joinpath(ROOT, dir)) ? g("-C", dir, "rev-parse", "HEAD") : ""
    (commit = g("rev-parse", "HEAD"), dirty = !isempty(dirty), dirty_files = dirty,
     giac_jl = sub("Giac.jl"), osr = sub(joinpath("osr", "Integration")))
end

const RUN_ID = Ref("")
"""
    run_id() -> String

The identifier of the current run, `<yyyymmdd-HHMMSS>_<host>` with `-dirty`
appended when the harness tree has uncommitted changes: BENCH_RUN_ID when
set (run_all.jl and supervise.jl set it for their children, so that every
record of one run carries the same id), else generated once per process.
"""
function run_id()
    if isempty(RUN_ID[])
        RUN_ID[] = get(ENV, "BENCH_RUN_ID", "")
        if isempty(RUN_ID[])
            RUN_ID[] = Dates.format(now(), "yyyymmdd-HHMMSS") * "_" * host_slug() * (git_info().dirty ? "-dirty" : "")
        end
    end
    RUN_ID[]
end

"""The 1-minute load average of the machine (Linux), NaN elsewhere: the noise a measurement was taken in."""
loadavg() = try parse(Float64, first(split(read("/proc/loadavg", String)))) catch; NaN end

const CALIB_SINK = Ref(0.0)
"""
    calibrate() -> seconds

A fixed pure-Julia workload (two hundred million square roots, the minimum of three
runs), timed at the start of every worker and recorded in machine.txt as
`calibration_s`: a scale to compare runs across machines, and a detector of a
perturbed run on the same machine.
"""
function calibrate()
    best = Inf
    for _ in 1:3
        t0 = time_ns()
        s = 0.0
        for i in 1:200_000_000
            s += sqrt(i)
        end
        CALIB_SINK[] = s
        best = min(best, (time_ns() - t0) / 1e9)
    end
    best
end

# ---------------------------------------------------------------------------
# Machine description
# ---------------------------------------------------------------------------

function write_machine_info(path::AbstractString, versions::AbstractVector; calibration = true)
    cpu = try
        first(Sys.cpu_info()).model
    catch
        "unknown"
    end
    gi = git_info()
    open(path, "a") do io
        println(io, "# ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))
        println(io, "run_id\t", run_id())
        println(io, "harness_commit\t", isempty(gi.commit) ? "unknown" : gi.commit)
        println(io, "harness_dirty\t", gi.dirty)
        isempty(gi.giac_jl) || println(io, "giac_jl_commit\t", gi.giac_jl)
        isempty(gi.osr) || println(io, "osr_commit\t", gi.osr)
        println(io, "host\t", gethostname())
        println(io, "host_slug\t", host_slug())
        println(io, "kernel\t", Sys.KERNEL, " ", Sys.MACHINE)
        println(io, "cpu\t", cpu, " x", Sys.CPU_THREADS)
        println(io, "memory_GiB\t", round(Sys.total_memory() / 2^30; digits = 1))
        println(io, "julia\t", VERSION)
        println(io, "julia_threads\t", Threads.nthreads())
        println(io, "load_avg\t", loadavg())
        calibration && println(io, "calibration_s\t", @sprintf("%.4g", calibrate()))
        for kv in versions
            println(io, first(kv), '\t', last(kv))
        end
        println(io)
    end
end

end # module
