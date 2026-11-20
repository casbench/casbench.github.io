# Rerun a few cases of a bench for one system and splice the new rows into
# the results file (after a fix of a task or of a check):
#
#   julia --startup-file=no lib/rerun.jl BENCH SYSTEM ENV_DIR TIMEOUT_S IDX...
#
# Each index runs in its own worker process (lib/worker.jl with BENCH_STOP),
# under the per-case time limit; the rows replace those of the same index in
# results/<host>/<BENCH>_<SYSTEM>.tsv (host: BENCH_HOST, else the hostname). The machine block of the
# rerun is appended to results/<host>/machine.txt by the worker as usual, and the new rows carry the
# rerun's own run id.

const ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ROOT, "lib", "common.jl"))
using .BenchCommon
const JULIA = Base.julia_cmd()

length(ARGS) >= 5 || error("usage: rerun.jl BENCH SYSTEM ENV_DIR TIMEOUT_S IDX...")
bench, system, envdir, timeout = ARGS[1], ARGS[2], ARGS[3], parse(Float64, ARGS[4])
idxs = parse.(Int, ARGS[5:end])
ENV["BENCH_RUN_ID"] = run_id()
out = joinpath(results_dir(), "$(bench)_$(system).tsv")
isfile(out) || error("no results file $out")

lines = readlines(out)
header, rows = lines[1], lines[2:end]
for i in idxs
    tmp = joinpath(results_dir(), ".rerun_$(bench)_$(system)_$(i).tsv")   # next to the results, so that machine.txt is the host's
    prog = tmp * ".progress"
    cmd = Cmd(addenv(`$JULIA --startup-file=no -t 1 --project=$envdir $(joinpath(ROOT, "lib", "worker.jl")) $bench $system $tmp $i $prog`,
                     "BENCH_STOP" => string(i)); dir = ROOT)
    proc = run(pipeline(ignorestatus(cmd); stdout = devnull, stderr = devnull); wait = false)
    t0 = time()
    while process_running(proc) && time() - t0 < timeout
        sleep(0.2)
    end
    if process_running(proc)
        kill(proc, Base.SIGKILL)
        new = join([bench, system, string(i), "case $i", "?", "timeout", "NaN", "NaN", "", "rerun: over the limit"], '\t')
    else
        got = isfile(tmp) ? filter(l -> !startswith(l, "bench\t") && split(l, '\t')[3] == string(i), readlines(tmp)) : String[]
        new = isempty(got) ? join([bench, system, string(i), "case $i", "?", "error", "NaN", "NaN", "", "rerun: worker exited with $(proc.exitcode)"], '\t') : got[1]
    end
    rm(tmp; force = true); rm(prog; force = true)
    j = findfirst(l -> split(l, '\t')[3] == string(i), rows)
    j === nothing ? push!(rows, new) : (rows[j] = new)
    println("[rerun] $bench/$system case $i: ", split(new, '\t')[6])
end
sort!(rows; by = l -> parse(Int, split(l, '\t')[3]))
write(out, join([header; rows], '\n') * "\n")
