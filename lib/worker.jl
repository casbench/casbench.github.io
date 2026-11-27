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
using Serialization

const BENCH, SYSTEM_KEY, OUT, START, PROGRESS = ARGS[1], ARGS[2], ARGS[3], parse(Int, ARGS[4]), ARGS[5]
const VERIFY_DEFAULT = get(ENV, "BENCH_VERIFICATION_SUPERVISED", "0") == "1" ? "1" : "0"
const VERIFY_ENABLED = get(ENV, "BENCH_VERIFY_INTEGRALS", VERIFY_DEFAULT) == "1" && BENCH in ("F_integration", "H_osr")
VERIFY_ENABLED && get(ENV, "BENCH_VERIFICATION_SUPERVISED", "0") != "1" &&
    error("integration self-verification requires lib/supervise.jl")

if BENCH == "A_interfaces"
    include(joinpath(@__DIR__, "..", BENCH, "adapter.jl"))
else
    include(joinpath(@__DIR__, "adapters", SYSTEM_KEY * ".jl"))
end
include(joinpath(@__DIR__, "..", BENCH, "problems.jl"))

# the machine block of a supervised run is written by its first worker: case 1, or the first case of a targeted
# run (BENCH_START_INDEX, as the hard Gröbner tier and single-case reruns use), not by a worker restarted later
if START == 1 || (BENCH == "G_groebner" && get(ENV, "BENCH_G_HARD", "0") == "1" && START == 33) ||
   START == parse(Int, get(ENV, "BENCH_START_INDEX", "1"))
    # the machine block goes next to the results file: results/<host>/machine.txt
    write_machine_info(joinpath(dirname(abspath(OUT)), "machine.txt"), [("bench", BENCH), ("system", SYSTEM), VERSIONS()...])
end
const T_LOAD = time() - T_LOAD0
START == 1 && append_record(OUT, Record(BENCH, SYSTEM, 0, "_load", "using", "verified", T_LOAD, NaN, "", "package load time"))

const STOP = parse(Int, get(ENV, "BENCH_STOP", string(length(PROBLEMS))))   # last problem index to run (single-problem reruns)
for i in START:STOP
    prob = PROBLEMS[i]
    BenchCommon.COMPLEX_SAMPLE_ENABLED[] = hasproperty(prob, :complex_point) ? prob.complex_point !== nothing : nothing
    op_label = BENCH == "G_groebner" && hasproperty(prob, :budget) ? "groebner_hard" : string(prob.op)
    write(PROGRESS, string(i, '\t', prob.name))
    opf = get(OPS, prob.op, missing)
    if opf === missing
        append_record(OUT, Record(BENCH, SYSTEM, i, prob.name, op_label, "unavailable", NaN, NaN, "", prob.note))
        continue
    end
    load = loadavg()                       # the noise the case is measured in
    reps = Float64[]
    verification_candidate = nothing
    numeric_request = OUT * ".numeric-request"
    numeric_started = Ref(false)
    pending_input = Ref("")
    function save_numeric_pending(answer, tf, tw=NaN; advance=true)
        pending = Record(BENCH, SYSTEM, i, prob.name, op_label, "unverified", tf, tw,
                         string(answer), "warm timing or numeric verification interrupted",
                         isempty(INPUT_LOG) ? pending_input[] : join(unique(INPUT_LOG), " ⏎ "),
                         NaN, "", load, run_id())
        tmp = numeric_request * ".tmp"
        open(io -> serialize(io, (record=pending,)), tmp, "w")
        mv(tmp, numeric_request; force=true)
        if advance && !numeric_started[]
            numeric_started[] = true
            write(PROGRESS, string(i, '\t', prob.name, '\t', "numeric"))
        end
    end
    rec = try
        args = prob.args(VAR)
        pending_input[] = "args: " * string(args)
        empty!(INPUT_LOG)
        if BENCH in ("G_groebner", "A_interfaces")
            checkpoint = OUT * ".input-checkpoint"
            write(checkpoint, "args: " * string(args))
            BenchCommon.INPUT_CHECKPOINT[] = () -> begin
                tmp = checkpoint * ".tmp"
                write(tmp, join(unique(INPUT_LOG), " ⏎ "))
                mv(tmp, checkpoint; force=true)
                BenchCommon.INPUT_CHECKPOINT[] = nothing
            end
        end
        integration = BENCH in ("F_integration", "H_osr")
        numeric_check = integration || BENCH == "J_rur"
        if integration
            BenchCommon.ANSWER_CALLBACK[] = (answer, stamp) -> begin
                numeric_started[] || save_numeric_pending(answer, (stamp - BenchCommon.TIME_CALL_START[]) / 1e9)
            end
        end
        first_answer = (answer, elapsed) -> begin
            if numeric_check
                declined = answer === nothing || (answer isa Tuple && !isempty(answer) && answer[1] === nothing) ||
                           (UNSOLVED(prob.op, answer) && !get(prob, :accept_unsolved, false))
                !declined && save_numeric_pending(answer, elapsed; advance=false)
            end
        end
        out, tf, tw = try
            time_call(() -> opf(args...); between = CLEARCACHE, repeats = isdefined(Main, :REPEATS) ? REPEATS : 5,
                      times = reps, answer_boundary = integration, after_first = first_answer)
        finally
            BenchCommon.ANSWER_CALLBACK[] = nothing
            BenchCommon.INPUT_CHECKPOINT[] = nothing
        end
        # A subprocess reports its own compute time as the warm time. Store
        # it before checkpointing, so an interrupted check retains that time.
        hasfield(typeof(out), :elapsed) && isfinite(out.elapsed) && (tw = out.elapsed)
        numeric_check && save_numeric_pending(out, tf, tw)
        input = isempty(INPUT_LOG) ? "args: " * string(args) : join(unique(INPUT_LOG), " ⏎ ")
        twall = isempty(reps) ? tf : minimum(reps)   # the harness's own wall time, the same meaning for every system
        note = prob.note
        check_elapsed = Ref(NaN)
        status = if out === nothing || (out isa Tuple && !isempty(out) && out[1] === nothing) || (UNSOLVED(prob.op, out) && !get(prob, :accept_unsolved, false))
            :unsolved
        else
            check_started = time_ns()
            try
                st = prob.check(out)
                st isa Tuple ? (note = string(st[2]); st[1]) : st   # a check may return (status, note)
            catch err
                note = "check raised: " * sprint(showerror, err)
                :unverified
            finally
                check_elapsed[] = (time_ns() - check_started) / 1e9
            end
        end
        if BENCH == "G_groebner" && isfinite(check_elapsed[])
            note *= "; check_wall_s=" * @sprintf("%.6g", check_elapsed[])
        end
        if hasfield(typeof(out), :process_peak_rss_kib)
            note *= "; process_peak_rss_kib=$(out.process_peak_rss_kib) (entire subprocess)"
        end
        # These benches' generic checks rely on numeric samples or counts;
        # reserve :verified for exact or symbolic checks in new records.
        exact_boolean = BENCH == "E_suite" && prob.name in
            ("A Mersenne prime of 89 bits",)
        if status === :verified && !exact_boolean && BENCH in ("B_cas", "D_coverage", "E_suite", "I_scale")
            status = :verified_numeric
        end
        if BENCH == "G_groebner" && get(ENV, "BENCH_G_HARD", "0") == "1" && hasproperty(prob, :budget)
            note = "hard tier; per-case budget $(prob.budget) s; " * note
        end
        record = Record(BENCH, SYSTEM, i, prob.name, op_label, string(status), tf, tw, string(out), note, input,
                        twall, join((@sprintf("%.6g", t) for t in reps), ";"), load, run_id())
        if VERIFY_ENABLED && status === :verified_numeric
            verification_candidate = (system=SYSTEM_KEY, answer=string(out), integrand=String(args[1]),
                                      variable=String(args[2]), record=record)
        end
        record
    catch err
        msg = sprint(showerror, err)
        if BENCH == "G_groebner" && get(ENV, "BENCH_G_HARD", "0") == "1" && hasproperty(prob, :budget)
            msg = "hard tier; per-case budget $(prob.budget) s; " * msg
        end
        # a system that says it cannot do the problem has not solved it; a crash is an error
        declined = occursin(r"NotImplemented|NotElementary|[Nn]ot implemented|cannot be solved|Cannot solve|Unable to solve|unsupported operation|no elementary antiderivative|no roots in radicals|no method for", msg)
        Record(BENCH, SYSTEM, i, prob.name, op_label, declined ? "unsolved" : "error", NaN, NaN, "", msg,
               isempty(INPUT_LOG) ? "" : join(unique(INPUT_LOG), " ⏎ "), NaN, "", load, run_id())
    end
    if verification_candidate !== nothing
        request = OUT * ".verify-request"
        response = OUT * ".verify-response"
        tmp = request * ".tmp"
        open(io -> serialize(io, verification_candidate), tmp, "w")
        mv(tmp, request; force=true)
        write(PROGRESS, string(i, '\t', prob.name, '\t', "verify"))
        while !isfile(response)
            sleep(0.05)
        end
        v = try
            open(deserialize, response)
        catch
            (status="verify_unsolved", time=NaN, command="")
        end
        rec = with_verification(rec, v.status, v.time, v.command)
        append_record(OUT, rec)
        rm(request; force=true)
        rm(response; force=true)
    else
        append_record(OUT, rec)
    end
    rm(numeric_request; force=true)
    rm(OUT * ".input-checkpoint"; force=true)
    GC.gc()
end
