# Bench C: integer factorisation. Giac.ifactors (through Giac.jl) against
# Primes.factor and LibPARI.factors (PARI/GP through LibPARI.jl).
#
#   julia --project=envs/intfactor C_ifactor/worker.jl C_ifactor SYSTEM OUT_TSV START_IDX PROGRESS_FILE
#   SYSTEM in giac | primes | pari
#
# Verification for every system: the product of the returned prime powers
# equals the input and every factor passes Primes.isprime (Baillie-PSW for
# BigInt, deterministic below 2^64) and Giac's isprime.
#
# Note on what is measured for Giac: GIAC_jll is built with PARI enabled and
# GMP-ECM disabled. In Giac's ifactor.cc, an integer below 10^71 is factored by
# Giac's own code (trial division, Pollard rho, then its multiple polynomial
# quadratic sieve); PARI's ifactor is only called at 10^71 and above. All
# inputs here are below 10^71, so this bench measures Giac's own sieve, not
# PARI through Giac. See benchmark/README.md.

const T_LOAD0 = time()
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
using Primes

const BENCH, SYSTEM_KEY, OUT, START, PROGRESS = ARGS[1], ARGS[2], ARGS[3], parse(Int, ARGS[4]), ARGS[5]
include(joinpath(@__DIR__, "inputs.jl"))

if SYSTEM_KEY == "giac"
    using Giac
    giac_eval("threads:=1")          # one Giac thread, as in every Giac column (docs/benches.md)
    const SYSTEM = "Giac.jl ifactor"
    FACT(n) = begin
        L = to_julia(invoke_cmd(:ifactors, giac_eval(string(n))))
        [BigInt(L[i]) => Int(L[i + 1]) for i in 1:2:length(L)]
    end
    VERSIONS() = ["Giac.jl" => string(pkgversion(Giac)), "GIAC_jll" => string(pkgversion(Giac.GIAC_jll)),
                  "giac_version" => string(giac_eval("version()"))]
    giac_isprime(p) = string(invoke_cmd(:isprime, giac_eval(string(p)))) == "true"
elseif SYSTEM_KEY == "primes"
    const SYSTEM = "Primes.jl factor"
    FACT(n) = [BigInt(p) => e for (p, e) in Primes.factor(n)]
    VERSIONS() = ["Primes" => string(pkgversion(Primes))]
    giac_isprime(p) = true
elseif SYSTEM_KEY == "pari"
    using LibPARI
    const SYSTEM = "LibPARI.jl factors"
    FACT(n) = [BigInt(p) => Int(e) for (p, e) in LibPARI.factors(pari(n))]
    VERSIONS() = ["LibPARI" => string(pkgversion(LibPARI)), "PARI_jll" => string(pkgversion(LibPARI.PARI_jll))]
    giac_isprime(p) = true
else
    error("unknown system $SYSTEM_KEY")
end

START == 1 && write_machine_info(joinpath(dirname(abspath(OUT)), "machine.txt"), [("bench", BENCH), ("system", SYSTEM), VERSIONS()...])
const T_LOAD = time() - T_LOAD0
START == 1 && append_record(OUT, Record(BENCH, SYSTEM, 0, "_load", "using", "verified", T_LOAD, NaN, "", "package load time"))

function verify(pairs, n)
    prod(p^e for (p, e) in pairs; init = big(1)) == n || return :wrong
    all(((p, e),) -> Primes.isprime(p) && giac_isprime(p), pairs) || return :wrong
    :verified
end

for i in START:length(INPUTS)
    (name, n, nf) = INPUTS[i]
    n = parse(BigInt, n)
    write(PROGRESS, string(i, '\t', name))
    load = loadavg()
    reps = Float64[]
    rec = try
        arg = n <= typemax(Int64) ? Int64(n) : n
        out, tf, tw = time_call(() -> FACT(arg); repeats = 3, warm_budget = 5.0, times = reps)
        st = verify(out, n)
        st === :verified && nf > 0 && length(out) != nf && (st = :wrong)
        Record(BENCH, SYSTEM, i, name, "ifactor", string(st), tf, tw,
               join(["$p^$e" for (p, e) in out], "*"), "$(ndigits(n)) digits", "",
               isempty(reps) ? tf : minimum(reps), join((string(round(t; sigdigits = 6)) for t in reps), ";"), load, run_id())
    catch e
        Record(BENCH, SYSTEM, i, name, "ifactor", "error", NaN, NaN, "", sprint(showerror, e), "", NaN, "", load, run_id())
    end
    append_record(OUT, rec)
    GC.gc()
end
