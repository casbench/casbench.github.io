# Generic worker for the benches with a problem file (B, D, E, F, G).
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
using Printf: @sprintf

const BENCH, SYSTEM_KEY, OUT, START, PROGRESS = ARGS[1], ARGS[2], ARGS[3], parse(Int, ARGS[4]), ARGS[5]

include(joinpath(@__DIR__, "adapters", SYSTEM_KEY * ".jl"))
include(joinpath(@__DIR__, "..", BENCH, "problems.jl"))

if START == 1
    # the machine block goes next to the results file: results/<host>/machine.txt
    write_machine_info(joinpath(dirname(abspath(OUT)), "machine.txt"), [("bench", BENCH), ("system", SYSTEM), VERSIONS()...])
end
const T_LOAD = time() - T_LOAD0
START == 1 && append_record(OUT, Record(BENCH, SYSTEM, 0, "_load", "using", "verified", T_LOAD, NaN, "", "package load time"))

const STOP = parse(Int, get(ENV, "BENCH_STOP", string(length(PROBLEMS))))   # last problem index to run (single-problem reruns)
for i in START:STOP
    prob = PROBLEMS[i]
    write(PROGRESS, string(i, '\t', prob.name))
    opf = get(OPS, prob.op, missing)
    if opf === missing
        append_record(OUT, Record(BENCH, SYSTEM, i, prob.name, string(prob.op), "unavailable", NaN, NaN, "", prob.note))
        continue
    end
    load = loadavg()                       # the noise the case is measured in
    reps = Float64[]
    rec = try
        args = prob.args(VAR)
        empty!(INPUT_LOG)
        out, tf, tw = time_call(() -> opf(args...); between = CLEARCACHE, repeats = isdefined(Main, :REPEATS) ? REPEATS : 5, times = reps)
        input = isempty(INPUT_LOG) ? "args: " * string(args) : join(unique(INPUT_LOG), " ⏎ ")
        twall = isempty(reps) ? tf : minimum(reps)   # the harness's own wall time, the same meaning for every system
        # a subprocess system reports its own compute time as the warm time (the first-call time includes its start-up)
        hasfield(typeof(out), :elapsed) && isfinite(out.elapsed) && (tw = out.elapsed)
        note = prob.note
        status = if out === nothing || (out isa Tuple && !isempty(out) && out[1] === nothing) || (UNSOLVED(prob.op, out) && !get(prob, :accept_unsolved, false))
            :unsolved
        else
            try
                st = prob.check(out)
                st isa Tuple ? (note = string(st[2]); st[1]) : st   # a check may return (status, note)
            catch err
                note = "check raised: " * sprint(showerror, err)
                :unverified
            end
        end
        Record(BENCH, SYSTEM, i, prob.name, string(prob.op), string(status), tf, tw, string(out), note, input,
               twall, join((@sprintf("%.6g", t) for t in reps), ";"), load, run_id())
    catch err
        msg = sprint(showerror, err)
        # a system that says it cannot do the problem has not solved it; a crash is an error
        declined = occursin(r"NotImplemented|NotElementary|[Nn]ot implemented|cannot be solved|Cannot solve|Unable to solve|unsupported operation|no elementary antiderivative|no roots in radicals|no method for", msg)
        Record(BENCH, SYSTEM, i, prob.name, string(prob.op), declined ? "unsolved" : "error", NaN, NaN, "", msg,
               isempty(INPUT_LOG) ? "" : join(unique(INPUT_LOG), " ⏎ "), NaN, "", load, run_id())
    end
    append_record(OUT, rec)
    GC.gc()
end
