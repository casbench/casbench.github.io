# Generic worker for benches B (CAS operations) and D (functional coverage).
#
#   julia --project=envs/<system> lib/worker.jl BENCH SYSTEM OUT_TSV START_IDX PROGRESS_FILE
#
# The adapter lib/adapters/<system>.jl defines, at top level:
#   SYSTEM::String, VAR::Dict{Symbol,Any}, OPS::Dict{Symbol,Any} (op name => function or missing),
#   EVAL(expr, vals::Dict{Symbol,Float64}) -> Float64/Complex or nothing,
#   NTERMS(expr), UNSOLVED(op, out)::Bool, CLEARCACHE(), VERSIONS()::Vector{Pair{String,String}}
# The problem file <BENCH>/problems.jl defines PROBLEMS::Vector{NamedTuple} with fields
#   name, op, args (function VAR -> tuple of arguments), check (function out -> status Symbol), note

const T_LOAD0 = time()
include(joinpath(@__DIR__, "common.jl"))
using .BenchCommon

const BENCH, SYSTEM_KEY, OUT, START, PROGRESS = ARGS[1], ARGS[2], ARGS[3], parse(Int, ARGS[4]), ARGS[5]

include(joinpath(@__DIR__, "adapters", SYSTEM_KEY * ".jl"))
include(joinpath(@__DIR__, "..", BENCH, "problems.jl"))

if START == 1
    write_machine_info(joinpath(@__DIR__, "..", "results", "machine.txt"),
                       [("bench", BENCH), ("system", SYSTEM), VERSIONS()...])
end
const T_LOAD = time() - T_LOAD0
START == 1 && append_record(OUT, Record(BENCH, SYSTEM, 0, "_load", "using", "verified", T_LOAD, NaN, "", "package load time"))

for i in START:length(PROBLEMS)
    p = PROBLEMS[i]
    write(PROGRESS, string(i, '\t', p.name))
    opf = get(OPS, p.op, missing)
    if opf === missing
        append_record(OUT, Record(BENCH, SYSTEM, i, p.name, string(p.op), "unavailable", NaN, NaN, "", p.note))
        continue
    end
    rec = try
        args = p.args(VAR)
        out, tf, tw = time_call(() -> opf(args...); between = CLEARCACHE)
        status = UNSOLVED(p.op, out) ? :unsolved : p.check(out)
        Record(BENCH, SYSTEM, i, p.name, string(p.op), string(status), tf, tw, string(out), p.note)
    catch e
        msg = sprint(showerror, e)
        Record(BENCH, SYSTEM, i, p.name, string(p.op), "error", NaN, NaN, "", msg)
    end
    append_record(OUT, rec)
    GC.gc()
end
