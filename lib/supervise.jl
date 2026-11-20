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

function supervise(envdir, worker, bench, system, out, timeout, extra)
    ENV["BENCH_RUN_ID"] = run_id()        # one run identifier for every worker of this supervision
    mkpath(dirname(abspath(out)))
    progress = out * ".progress"
    logfile = out * ".log"
    isfile(progress) && rm(progress)
    start = 1
    if get(ENV, "BENCH_RESUME", "0") == "1" && isfile(out)
        done = [r.idx for r in read_records(out)]
        start = isempty(done) ? 1 : maximum(done) + 1
        println("[supervise] $bench/$system: resuming at case $start")
    end
    while true
        # setsid: the worker leads a new process group, so that a timeout kills its subprocesses (Maxima, FriCAS,
        # Sage and their children) with it; the per-case limit is exported for the subprocess adapters' `timeout`
        # a fresh progress file for every worker: the memory check must not read the previous worker's case
        isfile(progress) && rm(progress)
        cmd = addenv(`setsid $(Base.julia_cmd()) --startup-file=no --project=$envdir $worker $bench $system $out $start $progress $extra`,
                     "BENCH_CASE_TIMEOUT" => string(round(Int, timeout)))
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
        while process_running(proc)
            sleep(0.25)
            p = isfile(progress) ? read(progress, String) : ""
            if p != last_progress
                last_progress = p
                last_change = time()
            end
            if !isempty(p) && time() - last_change > timeout
                elapsed = time() - last_change     # what the case had consumed when it was stopped (recorded as t_first)
                why = "timeout"
                killgroup("TERM")                # SIGTERM to the group; a worker blocked in a C call ignores it
                killed = true
                break
            end
            if !isempty(p) && time() - last_mem > 1
                last_mem = time()
                m = tree_rss(getpid(proc))
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
            idx, name = split(last_progress, '\t'; limit = 2)
            i = parse(Int, idx)
            if why == "timeout"
                append_record(out, Record(bench, system, i, name, "", "timeout", round(elapsed; digits = 2), NaN, "",
                                          "stopped after $(round(elapsed; digits = 1)) s, limit $(timeout) s (t_first is the time consumed when stopped)"))
            else
                append_record(out, Record(bench, system, i, name, "", "error", round(elapsed; digits = 2), NaN, "",
                                          "stopped after $(round(elapsed; digits = 1)) s: $why (t_first is the time consumed when stopped)"))
            end
            start = i + 1
            println("[supervise] $bench/$system: case $i ($name) stopped ($why); restarting at $(start)")
            continue
        end
        if proc.exitcode != 0 || proc.termsignal != 0   # a signal-terminated process keeps exitcode 0 in Julia
            # worker crashed (e.g. segfault inside a C++ call): record and skip the case
            p = isfile(progress) ? read(progress, String) : ""
            if isempty(p)
                println("[supervise] $bench/$system: worker exited with code $(proc.exitcode) before the first case; see $logfile")
                return
            end
            idx, name = split(p, '\t'; limit = 2)
            i = parse(Int, idx)
            recs = read_records(out)
            if !any(r -> r.idx == i, recs)
                append_record(out, Record(bench, system, i, name, "", "error", NaN, NaN, "", "worker exited with code $(proc.exitcode), signal $(proc.termsignal)"))
            end
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
