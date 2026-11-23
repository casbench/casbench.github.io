# Run a worker under a per-case time limit.
#
#   julia lib/supervise.jl ENV_DIR WORKER_SCRIPT BENCH SYSTEM OUT_TSV TIMEOUT_S [extra args...]
#
# The worker appends one record per case to OUT_TSV and, before starting a case,
# writes its index to OUT_TSV * ".progress". If the progress file is not
# updated and no record is appended within TIMEOUT_S seconds, the worker is
# killed, a `timeout` record is written for that case, and a fresh worker is
# started at the next case. Package loading and compilation happen before the
# first progress write, so they are not charged against the first case.
#
# A case whose worker tree grows past BENCH_MEM_LIMIT_GIB (default 5) of
# resident memory is stopped the same way and recorded as an error naming the
# limit: on 2026-11-20 a case that reached 7 GiB inside the 8 GiB machine got
# the whole machine killed by its host. With BENCH_RESUME=1 an existing
# OUT_TSV is kept and the run resumes after its last case, so that a queue
# cut by a reboot restarts where it stopped.
#
# This follows the scheme of SymJ.jl's bench/cas/supervise.jl (MIT), rewritten
# for this benchmark's record format.

include(joinpath(@__DIR__, "common.jl"))
using .BenchCommon
using Serialization

# every process below `pid` in the process tree (children, grandchildren, ...), from ps
function descendants(pid::Integer)
    parent = Dict{Int,Int}()
    for line in eachline(ignorestatus(`ps -e -o pid=,ppid=`))
        f = split(line)
        length(f) == 2 && (parent[parse(Int, f[1])] = parse(Int, f[2]))
    end
    out = Int[]; frontier = [pid]
    while !isempty(frontier)
        p = pop!(frontier)
        for (c, pp) in parent
            pp == p && !(c in out) && (push!(out, c); push!(frontier, c))
        end
    end
    out
end

const MEM_LIMIT = parse(Float64, get(ENV, "BENCH_MEM_LIMIT_GIB", "5")) * 2^30

# resident memory of a process (Linux), 0 elsewhere
rss(pid) = try
    m = match(r"VmRSS:\s+(\d+)", read("/proc/$pid/status", String))
    m === nothing ? 0 : parse(Int, m[1]) * 1024
catch
    0
end
tree_rss(pid) = sum(rss, [pid; descendants(pid)]; init = 0)

# The verification process is distinct from the timed answer worker. Its
# startup is not charged to the symbolic check; after readiness it has its
# own budget and a failure can never change the answer status.
function verify_phase(envdir, out)
    request = out * ".verify-request"
    ready = out * ".verify-ready"
    commandfile = out * ".verify-command"
    resultfile = out * ".verify-worker-result"
    for path in (ready, commandfile, resultfile)
        rm(path; force=true)
    end
    budget = parse(Float64, get(ENV, "BENCH_VERIFY_TIMEOUT", "60"))
    budget > 0 || error("BENCH_VERIFY_TIMEOUT must be positive")
    startup_limit = parse(Float64, get(ENV, "BENCH_VERIFY_STARTUP_TIMEOUT", "120"))
    script = get(ENV, "BENCH_VERIFY_WORKER", joinpath(@__DIR__, "verify_worker.jl"))
    cmd = addenv(`setsid $(Base.julia_cmd()) --startup-file=no --project=$envdir $script $request $resultfile $ready $commandfile`,
                 "BENCH_CASE_TIMEOUT" => string(ceil(Int, budget)))
    logfile = out * ".verify.log"
    proc = try
        run(pipeline(cmd; stdout=logfile, stderr=logfile, append=true); wait=false)
    catch
        return (status="verify_unsolved", time=NaN, command="")
    end
    start = time()
    ready_at = nothing
    timed_out = false
    while process_running(proc)
        if ready_at === nothing && isfile(ready)
            ready_at = time()
        end
        pid = try getpid(proc) catch; 0 end
        memory_exceeded = pid != 0 && tree_rss(pid) > MEM_LIMIT
        if (ready_at !== nothing && time() - ready_at > budget) ||
           (ready_at === nothing && time() - start > startup_limit) || memory_exceeded
            timed_out = ready_at !== nothing && time() - ready_at > budget
            if pid != 0
                kids = descendants(pid)
                run(ignorestatus(`kill -KILL -- -$pid`))
                isempty(kids) || run(ignorestatus(`kill -KILL $kids`))
            end
            break
        end
        sleep(0.1)
    end
    wait(proc)
    command = isfile(commandfile) ? read(commandfile, String) : ""
    result = if timed_out
        (status="verify_timeout", time=ready_at === nothing ? NaN : time() - ready_at, command=command)
    elseif isfile(resultfile)
        v = try open(deserialize, resultfile) catch; nothing end
        if v === nothing || !(v.status in ("verified_symbolic", "verify_unsolved"))
            (status="verify_unsolved", time=NaN, command=command)
        elseif isfinite(v.time) && v.time > budget
            # A short-lived worker may finish between supervisor polls.
            (status="verify_timeout", time=v.time, command=command)
        else
            (status=v.status, time=v.time, command=command)
        end
    else
        (status="verify_unsolved", time=NaN, command=command)
    end
    for path in (ready, commandfile, resultfile)
        rm(path; force=true)
    end
    result
end

function progress_parts(text)
    parts = split(text, '\t'; limit=3)
    length(parts) >= 2 && !isempty(parts[2]) || error("invalid worker progress")
    phase = length(parts) == 3 ? String(parts[3]) : "answer"
    phase in ("answer", "numeric", "verify") || error("invalid worker phase")
    (parse(Int, parts[1]), String(parts[2]), phase)
end

function respond_verification(out, result)
    response = out * ".verify-response"
    tmp = response * ".tmp"
    open(io -> serialize(io, result), tmp, "w")
    mv(tmp, response; force=true)
end

function supervise(envdir, worker, bench, system, out, timeout, extra)
    ENV["BENCH_RUN_ID"] = run_id()        # one run identifier for every worker of this supervision
    mkpath(dirname(abspath(out)))
    progress = out * ".progress"
    logfile = out * ".log"
    isfile(progress) && rm(progress)
    start = parse(Int, get(ENV, "BENCH_START_INDEX", "1"))
    start >= 1 || error("BENCH_START_INDEX must be positive")
    budgets = Dict{Int,Float64}()
    for item in split(get(ENV, "BENCH_CASE_BUDGETS", ""), ','; keepempty=false)
        parts = split(item, ':')
        length(parts) == 2 || error("invalid BENCH_CASE_BUDGETS entry")
        idx, budget = parse(Int, parts[1]), parse(Float64, parts[2])
        budget > 0 || error("case budget must be positive")
        budgets[idx] = budget
    end
    if get(ENV, "BENCH_RESUME", "0") == "1" && isfile(out)
        open(readline, out) == HEADER || error("cannot resume a historical result file with a different header: $out")
        done = [r.idx for r in read_records(out)]
        start = isempty(done) ? 1 : maximum(done) + 1
        println("[supervise] $bench/$system: resuming at case $start")
    end
    # A previous supervisor may have died between a request and its reply.
    # Resume reruns the unfinished case; a stale reply must never be attached
    # to a newly produced answer.
    for suffix in (".input-checkpoint", ".input-checkpoint.tmp", ".numeric-request", ".numeric-request.tmp", ".verify-request", ".verify-response", ".verify-ready", ".verify-command", ".verify-worker-result")
        rm(out * suffix; force=true)
    end
    while true
        # setsid: the worker leads a new process group, so that a timeout kills its subprocesses (Maxima, FriCAS,
        # Sage and their children) with it; the per-case limit is exported for the subprocess adapters' `timeout`
        # a fresh progress file for every worker: the memory check must not read the previous worker's case
        isfile(progress) && rm(progress)
        cmd = addenv(`setsid $(Base.julia_cmd()) --startup-file=no --project=$envdir $worker $bench $system $out $start $progress $extra`,
                     "BENCH_CASE_TIMEOUT" => string(round(Int, timeout)), "BENCH_VERIFICATION_SUPERVISED" => "1")
        proc = run(pipeline(cmd; stdout = logfile, stderr = logfile, append = true); wait = false)
        # the group, and every descendant (Sage's interfaces start FriCAS and giac in sessions of their own,
        # which a group kill does not reach): descendants are listed before the first kill
        function killgroup(sig)
            pid = getpid(proc)
            kids = descendants(pid)
            run(ignorestatus(`kill -$sig -- -$pid`))
            isempty(kids) || run(ignorestatus(`kill -$sig $kids`))
        end
        last_progress = ""
        last_change = time()
        killed = false
        elapsed = NaN
        why = ""
        last_mem = time()
        handled_verification = ""
        while process_running(proc)
            sleep(0.25)
            p = isfile(progress) ? read(progress, String) : ""
            # The worker writes this small file in place. Ignore an incomplete
            # observation while it is being replaced, rather than treating it
            # as a case transition or crashing the supervisor.
            parsed = isempty(p) ? nothing : (try progress_parts(p) catch; nothing end)
            parsed === nothing && (p = last_progress)
            if p != last_progress
                last_progress = p
                last_change = time()
            end
            if !isempty(p) && p != handled_verification
                _, _, phase = progress_parts(p)
                if phase == "verify" && isfile(out * ".verify-request")
                    result = verify_phase(envdir, out)
                    respond_verification(out, result)
                    handled_verification = p
                    last_change = time()
                    process_running(proc) || break
                end
            end
            current = isempty(p) ? nothing : progress_parts(p)
            phase_timeout = current !== nothing && current[3] == "numeric" ?
                parse(Float64, get(ENV, "BENCH_NUMERIC_VERIFY_TIMEOUT", "60")) :
                current === nothing ? timeout : get(budgets, current[1], timeout)
            phase_timeout > 0 || error("phase timeout must be positive")
            if !isempty(p) && time() - last_change > phase_timeout
                elapsed = time() - last_change     # what the case had consumed when it was stopped (recorded as t_first)
                why = "timeout"
                killgroup("TERM")                # SIGTERM to the group; a worker blocked in a C call ignores it
                killed = true
                break
            end
            if !isempty(p) && time() - last_mem > 1
                last_mem = time()
                pid = try getpid(proc) catch; 0 end
                m = pid == 0 ? 0 : tree_rss(pid)
                if m > MEM_LIMIT
                    elapsed = time() - last_change
                    why = "memory $(round(m / 2^30; digits = 2)) GiB over the limit $(round(MEM_LIMIT / 2^30; digits = 1)) GiB"
                    killgroup("KILL")            # no grace: the machine itself is at risk
                    killed = true
                    break
                end
            end
        end
        if killed
            t0 = time()
            while process_running(proc) && time() - t0 < 10
                sleep(0.25)
            end
            process_running(proc) && killgroup("KILL")
        end
        wait(proc)
        if killed
            i, name, phase = progress_parts(last_progress)
            case_budget = get(budgets, i, timeout)
            case_op = bench == "G_groebner" && get(ENV, "BENCH_G_HARD", "0") == "1" ? "groebner_hard" : ""
            checkpoint = out * ".input-checkpoint"
            saved_input = isfile(checkpoint) ? read(checkpoint, String) : ""
            request = out * ".verify-request"
            pending = phase == "verify" && isfile(request) ? (try open(deserialize, request) catch; nothing end) : nothing
            already_recorded = any(r -> r.idx == i, read_records(out))
            if already_recorded
                # The worker may have appended its answer just before it was stopped.
                # Never append a second row for the same case.
                nothing
            elseif pending !== nothing
                response = out * ".verify-response"
                v = isfile(response) ? (try open(deserialize, response) catch; nothing end) : nothing
                v === nothing && (v = (status="verify_unsolved", time=NaN, command=""))
                append_record(out, with_verification(pending.record, v.status, v.time, v.command))
            elseif phase in ("answer", "numeric") && bench in ("F_integration", "H_osr", "J_rur") && isfile(out * ".numeric-request")
                numeric = try open(deserialize, out * ".numeric-request") catch; nothing end
                if numeric !== nothing
                    append_record(out, numeric.record)
                else
                    append_record(out, Record(bench, system, i, name, "", "unverified", NaN, NaN, "", "numeric verification interrupted"))
                end
            elseif why == "timeout"
                append_record(out, Record(bench, system, i, name, case_op, "timeout", round(elapsed; digits = 2), NaN, "",
                                          "stopped after $(round(elapsed; digits = 1)) s, limit $(case_budget) s (t_first is the time consumed when stopped)", saved_input))
            else
                append_record(out, Record(bench, system, i, name, case_op, "error", round(elapsed; digits = 2), NaN, "",
                                          "stopped after $(round(elapsed; digits = 1)) s: $why; case budget $(case_budget) s (t_first is the time consumed when stopped)", saved_input))
            end
            rm(request; force=true)
            rm(out * ".numeric-request"; force=true)
            rm(out * ".input-checkpoint"; force=true)
            rm(out * ".verify-response"; force=true)
            start = i + 1
            println("[supervise] $bench/$system: case $i ($name) stopped ($why); restarting at $(start)")
            continue
        end
        if proc.exitcode != 0 || proc.termsignal != 0   # a signal-terminated process keeps exitcode 0 in Julia
            # worker crashed (e.g. segfault inside a C++ call): record and skip the case
            p = isfile(progress) ? read(progress, String) : ""
            if isempty(p)
                error("[supervise] $bench/$system: worker exited with code $(proc.exitcode), signal $(proc.termsignal) before the first case; see $logfile")
            end
            i, name, phase = progress_parts(p)
            case_op = bench == "G_groebner" && get(ENV, "BENCH_G_HARD", "0") == "1" ? "groebner_hard" : ""
            checkpoint = out * ".input-checkpoint"
            saved_input = isfile(checkpoint) ? read(checkpoint, String) : ""
            recs = read_records(out)
            if !any(r -> r.idx == i, recs)
                # If the answer worker crashes while waiting for verification,
                # retain its completed answer and classify only verification.
                request = out * ".verify-request"
                pending = phase == "verify" && isfile(request) ? (try open(deserialize, request) catch; nothing end) : nothing
                if pending !== nothing
                    response = out * ".verify-response"
                    v = isfile(response) ? (try open(deserialize, response) catch; nothing end) : nothing
                    v === nothing && (v = (status="verify_unsolved", time=NaN, command=""))
                    append_record(out, with_verification(pending.record, v.status, v.time, v.command))
                elseif phase in ("answer", "numeric") && bench in ("F_integration", "H_osr", "J_rur") && isfile(out * ".numeric-request")
                    numeric = try open(deserialize, out * ".numeric-request") catch; nothing end
                    numeric === nothing || append_record(out, numeric.record)
                    numeric === nothing && append_record(out, Record(bench, system, i, name, "", "unverified", NaN, NaN, "", "numeric verification interrupted"))
                else
                    append_record(out, Record(bench, system, i, name, case_op, "error", NaN, NaN, "", "worker exited with code $(proc.exitcode), signal $(proc.termsignal); case budget $(get(budgets, i, timeout)) s", saved_input))
                end
            end
            rm(out * ".verify-request"; force=true)
            rm(out * ".numeric-request"; force=true)
            rm(out * ".input-checkpoint"; force=true)
            rm(out * ".verify-response"; force=true)
            start = i + 1
            println("[supervise] $bench/$system: worker crashed on case $i ($name); restarting at $(start)")
            continue
        end
        break
    end
    isfile(progress) && rm(progress)
    println("[supervise] $bench/$system: done")
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) >= 6 || error("usage: supervise.jl ENV_DIR WORKER BENCH SYSTEM OUT_TSV TIMEOUT_S [extra...]")
    envdir, worker, bench, system, out, timeout = ARGS[1:6]
    supervise(envdir, worker, bench, system, out, parse(Float64, timeout), ARGS[7:end])
end
