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
# This follows the scheme of SymJ.jl's bench/cas/supervise.jl (MIT), rewritten
# for this benchmark's record format.

include(joinpath(@__DIR__, "common.jl"))
using .BenchCommon

function supervise(envdir, worker, bench, system, out, timeout, extra)
    progress = out * ".progress"
    logfile = out * ".log"
    isfile(progress) && rm(progress)
    start = 1
    while true
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$envdir $worker $bench $system $out $start $progress $extra`
        proc = run(pipeline(cmd; stdout = logfile, stderr = logfile, append = true); wait = false)
        last_progress = ""
        last_change = time()
        killed = false
        while process_running(proc)
            sleep(0.25)
            p = isfile(progress) ? read(progress, String) : ""
            if p != last_progress
                last_progress = p
                last_change = time()
            end
            if !isempty(p) && time() - last_change > timeout
                kill(proc)
                killed = true
                break
            end
        end
        wait(proc)
        if killed
            idx, name = split(last_progress, '\t'; limit = 2)
            i = parse(Int, idx)
            append_record(out, Record(bench, system, i, name, "", "timeout", NaN, NaN, "", "killed after $(timeout)s"))
            start = i + 1
            println("[supervise] $bench/$system: case $i ($name) timed out; restarting at $(start)")
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
