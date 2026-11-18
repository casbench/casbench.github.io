# Shared helpers for the Giac.jl paper benchmarks.
#
# Every bench writes one tab-separated line per (system, case) into
# benchmark/results/<bench>_<system>.tsv. The columns are fixed by HEADER below.
# Nothing here depends on any CAS package, so the file can be included from
# every environment.

module BenchCommon

using Dates
using Printf

export Record, HEADER, append_record, read_records, write_machine_info,
       time_call, truncate_str, clean, numeq, POINTS, POINTS_POS

# ---------------------------------------------------------------------------
# Records
# ---------------------------------------------------------------------------

# status vocabulary (one of these strings in the `status` column):
#   verified     the system returned an answer and the check passed
#   wrong        the system returned an answer and the check failed
#   unverified   an answer was returned but could not be evaluated numerically
#   unsolved     the system returned the problem unevaluated / incomplete
#   unavailable  the operation does not exist in this system
#   error        the call raised an exception (message in `note`)
#   timeout      the case exceeded the per-case time limit (killed by supervise.jl)
const STATUSES = ("verified", "wrong", "unverified", "unsolved", "unavailable", "error", "timeout")

struct Record
    bench::String
    system::String
    idx::Int
    case::String
    op::String
    status::String
    t_first::Float64   # seconds, first call in a fresh process (includes compilation)
    t_warm::Float64    # seconds, minimum over repeated calls (NaN if not measured)
    result::String     # truncated textual result
    note::String
end

const HEADER = "bench\tsystem\tidx\tcase\top\tstatus\tt_first_s\tt_warm_s\tresult\tnote"

clean(s) = replace(String(string(s)), '\t' => ' ', '\n' => ' ', '\r' => ' ')
truncate_str(s, n = 200) = (s = clean(s); length(s) > n ? first(s, n) * "..." : s)

function append_record(path::AbstractString, r::Record)
    new = !isfile(path) || filesize(path) == 0
    open(path, "a") do io
        new && println(io, HEADER)
        println(io, join([r.bench, r.system, string(r.idx), clean(r.case), r.op, r.status,
                          @sprintf("%.6g", r.t_first), @sprintf("%.6g", r.t_warm),
                          truncate_str(r.result), truncate_str(r.note, 300)], '\t'))
    end
end

function read_records(path::AbstractString)
    out = Record[]
    isfile(path) || return out
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        f = split(line, '\t'; keepempty = true)
        length(f) == 10 || continue
        push!(out, Record(f[1], f[2], parse(Int, f[3]), f[4], f[5], f[6],
                          parse(Float64, f[7]), parse(Float64, f[8]), f[9], f[10]))
    end
    out
end

# ---------------------------------------------------------------------------
# Timing
# ---------------------------------------------------------------------------

"""
    time_call(f; repeats=5, warm_budget=10.0, between=() -> nothing)

Call `f()` once and record the wall-clock time of that first call (which, in a
fresh process, includes compilation). If it took less than `warm_budget`
seconds, call it `repeats` more times and record the minimum. `between` runs
before every repeated call (used to clear SymPy's cache). Returns
`(result, t_first, t_warm)`; `t_warm` is `NaN` when not measured.

Calls that take less than a millisecond are re-timed in a loop of `n` calls so
that the reported per-call time has microsecond resolution.
"""
function time_call(f; repeats = 5, warm_budget = 10.0, between = () -> nothing)
    t0 = time_ns()
    out = f()
    t_first = (time_ns() - t0) / 1e9
    t_warm = NaN
    if t_first < warm_budget
        best = Inf
        for _ in 1:repeats
            between()
            if t_first < 1e-3
                n = 200
                t0 = time_ns()
                for _ in 1:n
                    f()
                end
                dt = (time_ns() - t0) / 1e9 / n
            else
                t0 = time_ns()
                f()
                dt = (time_ns() - t0) / 1e9
            end
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
# Machine description
# ---------------------------------------------------------------------------

function write_machine_info(path::AbstractString, versions::AbstractVector)
    cpu = try
        first(Sys.cpu_info()).model
    catch
        "unknown"
    end
    open(path, "a") do io
        println(io, "# ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))
        println(io, "host\t", gethostname())
        println(io, "kernel\t", Sys.KERNEL, " ", Sys.MACHINE)
        println(io, "cpu\t", cpu, " x", Sys.CPU_THREADS)
        println(io, "memory_GiB\t", round(Sys.total_memory() / 2^30; digits = 1))
        println(io, "julia\t", VERSION)
        println(io, "julia_threads\t", Threads.nthreads())
        for kv in versions
            println(io, first(kv), '\t', last(kv))
        end
        println(io)
    end
end

end # module
