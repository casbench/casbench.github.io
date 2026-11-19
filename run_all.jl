# Run every bench and regenerate the tables.
#
#   julia benchmark/run_all.jl [A|B|C|D ...]
#
# Environment variables:
#   BENCH_TIMEOUT_B, BENCH_TIMEOUT_D   per-case limit in seconds (default 120)
#   BENCH_TIMEOUT_C                    per-case limit for integer factorisation (default 600)
#   BENCH_TIMEOUT_E                    per-case limit for the problem suite (default 60)
#   BENCH_SKIP_INSTANTIATE=1           do not call Pkg.instantiate on the environments
#   JULIA_CONDAPKG_BACKEND / JULIA_PYTHONCALL_EXE  forwarded to the SymPy environment
#
# Each bench/system pair runs in its own process under lib/supervise.jl, with
# one Julia thread, from the environment benchmark/envs/<system>.

import Pkg

const ROOT = @__DIR__
const RESULTS = joinpath(ROOT, "results")
mkpath(RESULTS)
const JULIA = Base.julia_cmd()

envs = Dict("giac" => joinpath(ROOT, "envs", "giac"),
            "symbolics" => joinpath(ROOT, "envs", "symbolics"),
            "sympy" => joinpath(ROOT, "envs", "sympy"),
            "symj" => joinpath(ROOT, "envs", "symj"),
            "intfactor" => joinpath(ROOT, "envs", "intfactor"))

benches = isempty(ARGS) ? ["A", "B", "C", "D", "E"] : ARGS
tB = get(ENV, "BENCH_TIMEOUT_B", "120")
tD = get(ENV, "BENCH_TIMEOUT_D", "120")
tC = get(ENV, "BENCH_TIMEOUT_C", "600")
tE = get(ENV, "BENCH_TIMEOUT_E", "60")

if get(ENV, "BENCH_SKIP_INSTANTIATE", "0") != "1"
    for (k, dir) in envs
        println("[run_all] instantiating $dir")
        run(`$JULIA --startup-file=no --project=$dir -e 'import Pkg; Pkg.instantiate(); Pkg.precompile()'`)
    end
end

supervise(env, worker, bench, system, out, timeout) =
    run(`$JULIA --startup-file=no -t 1 $(joinpath(ROOT, "lib", "supervise.jl")) $env $worker $bench $system $out $timeout`)

for b in benches
    if b == "A"
        out = joinpath(RESULTS, "A_ffi_giac.tsv")
        run(`$JULIA --startup-file=no -t 1 --project=$(envs["giac"]) $(joinpath(ROOT, "A_ffi", "run.jl")) $out`)
    elseif b in ("B", "D", "E")
        bench = b == "B" ? "B_cas" : b == "D" ? "D_coverage" : "E_suite"
        for sys in ("giac", "symbolics", "sympy", "symj")
            out = joinpath(RESULTS, "$(bench)_$(sys).tsv")
            isfile(out) && rm(out)
            supervise(envs[sys], joinpath(ROOT, "lib", "worker.jl"), bench, sys, out, b == "B" ? tB : b == "D" ? tD : tE)
        end
    elseif b == "C"
        for sys in ("giac", "primes", "pari")
            out = joinpath(RESULTS, "C_ifactor_$(sys).tsv")
            isfile(out) && rm(out)
            supervise(envs["intfactor"], joinpath(ROOT, "C_ifactor", "worker.jl"), "C_ifactor", sys, out, tC)
        end
    else
        error("unknown bench $b")
    end
end

run(`$JULIA --startup-file=no $(joinpath(ROOT, "make_tables.jl"))`)
