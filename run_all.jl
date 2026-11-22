# Run every bench and regenerate the tables.
#
#   julia benchmark/run_all.jl [A|B|C|D ...]
#
# Environment variables:
#   BENCH_TIMEOUT_B, BENCH_TIMEOUT_D   per-case limit in seconds (default 120)
#   BENCH_TIMEOUT_C                    per-case limit for integer factorisation (default 600)
#   BENCH_TIMEOUT_E                    per-case limit for the problem suite (default 60)
#   BENCH_SKIP_INSTANTIATE=1           do not call Pkg.instantiate on the environments
#   BENCH_HOST                         name of this host in results/<host>/ (default: the hostname)
#   BENCH_ALLOW_DIRTY=1                run from a tree with uncommitted changes (the run is then marked -dirty)
#   BENCH_RUN_ID                       identifier of the run (default: <date>_<host>, generated here)
#   BENCH_RESUME=1                     keep the existing results files and resume each one after its last case
#   BENCH_MEM_LIMIT_GIB                resident memory a case's worker tree may reach before it is stopped (default 5)
#   BENCH_VERIFY_INTEGRALS=0           disable symbolic self-checks in F and H (enabled by default under supervisor)
#   BENCH_VERIFY_TIMEOUT               symbolic check limit in seconds (default 60, independent of answer time)
#   JULIA_CONDAPKG_BACKEND / JULIA_PYTHONCALL_EXE  forwarded to the SymPy environment
#
# Each bench/system pair runs in its own process under lib/supervise.jl, with
# one Julia thread, from the environment benchmark/envs/<system>. The results
# go to results/<host>/<bench>_<system>.tsv with machine.txt next to them.

import Pkg

const ROOT = @__DIR__
include(joinpath(ROOT, "lib", "common.jl"))
using .BenchCommon
const JULIA = Base.julia_cmd()

# a run must be identifiable: the harness commit goes into machine.txt and every record carries the run id
let gi = git_info()
    if gi.dirty && get(ENV, "BENCH_ALLOW_DIRTY", "0") != "1"
        error("the working tree has uncommitted changes outside results/, so the run could not be identified by a commit; " *
              "commit them, or set BENCH_ALLOW_DIRTY=1 to run anyway (the run id is then marked -dirty):\n" * gi.dirty_files)
    end
end
ENV["BENCH_RUN_ID"] = run_id()
const RESULTS = results_dir()
println("[run_all] run ", ENV["BENCH_RUN_ID"], " -> ", RESULTS)

envs = Dict("giac" => joinpath(ROOT, "envs", "giac"),
            "symbolics" => joinpath(ROOT, "envs", "symbolics"),
            "sympy" => joinpath(ROOT, "envs", "sympy"),
            "symj" => joinpath(ROOT, "envs", "symj"),
            "intfactor" => joinpath(ROOT, "envs", "intfactor"),
            "groebner" => joinpath(ROOT, "envs", "groebner"),
            "msolve" => joinpath(ROOT, "envs", "msolve"),
            "maxima" => joinpath(ROOT, "envs", "subprocess"),
            "fricas" => joinpath(ROOT, "envs", "subprocess"),
            "sage_giac" => joinpath(ROOT, "envs", "subprocess"), "sage_maxima" => joinpath(ROOT, "envs", "subprocess"),
            "sage_fricas" => joinpath(ROOT, "envs", "subprocess"), "sage_sympy" => joinpath(ROOT, "envs", "subprocess"),
            "sage_singular" => joinpath(ROOT, "envs", "subprocess"), "macaulay2" => joinpath(ROOT, "envs", "subprocess"),
            "symengine" => joinpath(ROOT, "envs", "symengine"),
            "computeengine" => joinpath(ROOT, "envs", "subprocess"))

benches = isempty(ARGS) ? ["A", "B", "C", "D", "E", "F", "G", "H", "I"] : ARGS
tB = get(ENV, "BENCH_TIMEOUT_B", "120")
tD = get(ENV, "BENCH_TIMEOUT_D", "120")
tC = get(ENV, "BENCH_TIMEOUT_C", "600")
tE = get(ENV, "BENCH_TIMEOUT_E", "60")
tG = get(ENV, "BENCH_TIMEOUT_G", "300")
tF = get(ENV, "BENCH_TIMEOUT_F", "30")
tH = get(ENV, "BENCH_TIMEOUT_H", "30")
tI = get(ENV, "BENCH_TIMEOUT_I", "300")

if get(ENV, "BENCH_SKIP_INSTANTIATE", "0") != "1"
    for (k, dir) in envs
        println("[run_all] instantiating $dir")
        run(`$JULIA --startup-file=no --project=$dir -e 'import Pkg; Pkg.instantiate(); Pkg.precompile()'`)
    end
end

const RESUME = get(ENV, "BENCH_RESUME", "0") == "1"
supervise(env, worker, bench, system, out, timeout) =
    run(`$JULIA --startup-file=no -t 1 $(joinpath(ROOT, "lib", "supervise.jl")) $env $worker $bench $system $out $timeout`)
function fresh(out)
    if !RESUME && isfile(out)
        error("refusing to replace existing results $out; choose a new BENCH_HOST or explicitly resume a compatible run")
    end
    true
end

for b in benches
    if b == "A"
        out = joinpath(RESULTS, "A_ffi_giac.tsv")
        isfile(out) && error("bench A cannot resume an existing result file; choose a new BENCH_HOST")
        run(`$JULIA --startup-file=no -t 1 --project=$(envs["giac"]) $(joinpath(ROOT, "A_ffi", "run.jl")) $out`)
    elseif b in ("B", "D", "E")
        bench = b == "B" ? "B_cas" : b == "D" ? "D_coverage" : "E_suite"
        for sys in ("giac", "symbolics", "sympy", "symj", "symengine")
            out = joinpath(RESULTS, "$(bench)_$(sys).tsv")
            fresh(out)
            supervise(envs[sys], joinpath(ROOT, "lib", "worker.jl"), bench, sys, out, b == "B" ? tB : b == "D" ? tD : tE)
        end
    elseif b == "F"
        for sys in ("giac", "symbolics", "sympy", "symj", "maxima", "fricas", "sage_giac", "sage_maxima", "sage_fricas", "sage_sympy", "computeengine")
            out = joinpath(RESULTS, "F_integration_$(sys).tsv")
            fresh(out)
            supervise(envs[sys], joinpath(ROOT, "lib", "worker.jl"), "F_integration", sys, out, tF)
        end
    elseif b == "I"
        for sys in ("giac", "symbolics", "symengine", "symj", "sympy", "computeengine")
            out = joinpath(RESULTS, "I_scale_$(sys).tsv")
            fresh(out)
            supervise(envs[sys], joinpath(ROOT, "lib", "worker.jl"), "I_scale", sys, out, tI)
        end
    elseif b == "H"
        for sys in ("giac", "symbolics", "sympy", "symj", "maxima", "fricas", "sage_giac", "sage_maxima", "sage_fricas", "sage_sympy", "computeengine")
            out = joinpath(RESULTS, "H_osr_$(sys).tsv")
            fresh(out)
            supervise(envs[sys], joinpath(ROOT, "lib", "worker.jl"), "H_osr", sys, out, tH)
        end
    elseif b == "G"
        for sys in ("giac", "groebner", "msolve", "sympy", "sage_singular", "sage_giac", "macaulay2")
            out = joinpath(RESULTS, "G_groebner_$(sys).tsv")
            fresh(out)
            supervise(envs[sys], joinpath(ROOT, "lib", "worker.jl"), "G_groebner", sys, out, tG)
        end
    elseif b == "C"
        for sys in ("giac", "primes", "pari")
            out = joinpath(RESULTS, "C_ifactor_$(sys).tsv")
            fresh(out)
            supervise(envs["intfactor"], joinpath(ROOT, "C_ifactor", "worker.jl"), "C_ifactor", sys, out, tC)
        end
    else
        error("unknown bench $b")
    end
end

run(`$JULIA --startup-file=no $(joinpath(ROOT, "make_tables.jl"))`)
