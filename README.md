# Benchmarks for the JuliaCon Proceedings paper on Giac.jl

Every number in `paper/paper.tex` that is not attributed to a third party comes
from a script in this directory, run on fixed inputs that are stored in the
repository, with the environment pinned by `flake.lock` and the
`Manifest.toml` of each Julia environment.

## Layout

This repository holds the paper (`paper/`) and the benches (`benchmark/`);
Giac.jl itself is the git submodule `Giac.jl`, pinned to the commit the
benches were run against. Clone with `git clone --recurse-submodules` or run
`git submodule update --init` once; the Giac environments point at it by
path (`../../../Giac.jl`).

## One command

```sh
nix run ./benchmark#bench            # all four benches, then the tables
nix run ./benchmark#bench -- A C     # a subset
```

Without Nix: `julia --startup-file=no benchmark/run_all.jl` with Julia 1.13,
a Python 3 interpreter that can `import sympy` (set `JULIA_PYTHONCALL_EXE` to
it and `JULIA_CONDAPKG_BACKEND=Null`, otherwise CondaPkg installs its own),
and network access for `Pkg.instantiate`.

Every bench/system pair runs in its own Julia process with one thread, from
its own environment under `envs/`, under `lib/supervise.jl`, which enforces a
per-case time limit (`BENCH_TIMEOUT_B`, `BENCH_TIMEOUT_C`, `BENCH_TIMEOUT_D`;
defaults 120 s, 600 s, 120 s) and restarts the worker at the next case after
a timeout or a crash. Results are appended to `results/<bench>_<system>.tsv`
(one line per case: status, first-call time, warm time, textual result,
note) and `make_tables.jl` turns them into `paper/tables/*.tex` and
`results/summary.md`. `results/machine.txt` and `results/environment.txt`
record the host, the Julia and package versions, `versioninfo(verbose=true)`,
`lscpu` and the flake and nixpkgs revisions.

## The four benches

**A, FFI overhead** (`A_ffi/run.jl`, Giac.jl only). One call of `sin`,
`normal`, `diff`, `factor` and `expand` through each dispatch level of
Giac.jl: the raw CxxWrap binding on a cached C++ `Gen` (tier-1 binding, or
`apply_func1` by name when no tier-1 binding exists), the tier-1 Julia wrapper
(`Base.sin(::GiacExpr)`), `invoke_cmd` with the direct-`Gen` fast path,
`invoke_cmd` with the string path forced, and `giac_eval` on a pre-built
string. Reported in microseconds per call, minimum over 7 rounds of 2000
calls, inputs rotating through a pool of 8 expressions so that Giac's
memoisation of an identical repeated call does not dominate. Every level is
checked to return the same printed result.

**B, CAS operations** (`B_cas/problems.jl`; Giac.jl, Symbolics.jl, SymPy,
SymJ.jl). `expand`, `factor`, `integrate` and `simplify` on 34 fixed inputs.
Each answer is verified, not only timed: expansion by numeric equality with
the input at three fixed points and the expected number of terms;
factorisation by the product of the returned factors and the number of
irreducible factors over the rationals; integration by a central finite
difference of the antiderivative against the integrand at three points;
simplification by numeric equality and a bound on the printed size. Two
times are recorded: the first call in a fresh process (which includes
compilation for the Julia packages, as in J. Verzani's comparisons) and the
minimum of five repeated calls (SymPy's cache is cleared between repeats).

**C, integer factorisation** (`C_ifactor/`; `Giac.ifactors`, `Primes.factor`,
`LibPARI.factors`). Ordinary `Int64` values, smooth integers, and semiprimes
of 20, 30, 40, 50 and 60 digits, all fixed in `C_ifactor/inputs.jl`. Each
result is verified: the product of the prime powers equals the input and each
factor passes `Primes.isprime` (and Giac's `isprime` for the Giac rows).
What this bench measures for Giac: `GIAC_jll` 2.0.3 is built with PARI
enabled and GMP-ECM disabled; in Giac's `ifactor.cc`, integers below 10^71
are factored by Giac's own code (trial division by primes up to 997, Pollard
rho, then its multiple-polynomial quadratic sieve) and PARI's `ifactor` is
only called at 10^71 and above. All inputs here are below 10^71, so the Giac
column is Giac's own sieve, not PARI through Giac.

**D, functional coverage** (`D_coverage/problems.jl`; same four systems). One
problem per capability, starting with the three headline problems of the
JuliaCon 2026 talk (`factor(x^4-1)`, `solve(cos(x)=1/2)` exactly,
`21u+28v=7` over the integers), then Laplace and Z transforms, partial
fractions, an initial value problem, limits, series, closed-form sums, a
non-elementary integral, polynomial gcd, resultant, discriminant, a Groebner
basis, factorisation over the complex numbers, a symbolic determinant and
eigenvalues, a 60-digit factorisation, and simplification under an
assumption. The status vocabulary separates `unavailable` (no such operation
in the system, as wired in `lib/adapters/<system>.jl`) from `unsolved`
(returned unevaluated or incomplete), `wrong`, `unverified`, `error` and
`timeout`.

## Adapters

`lib/adapters/{giac,symbolics,sympy,symj}.jl` define the same small
interface (`OPS`, `EVAL`, `NTERMS`, `UNSOLVED`, `VERSIONS`). Their structure
follows the worker files of SymJ.jl's `bench/cas` comparison (MIT), which
pair Symbolics.jl and SymJ.jl with GruntzLimit.jl for limits and
RischIntegrate.jl for integrals, since neither has symbolic integration or
limits of its own. Symbolics.jl's polynomial factorisation goes through its
Nemo extension (`factor_use_nemo`); an operation an adapter maps to `missing`
is reported as `unavailable`. SymJ.jl is not in the General registry at the
time of writing and is pinned by URL and tree hash in `envs/symj`.

## Reproducibility notes

- Inputs are never drawn at run time. The semiprimes of bench C were produced
  once by `C_ifactor/generate_inputs.jl` (next prime after fixed starting
  points) and pasted into `inputs.jl`.
- The reported numbers were obtained on a Converix virtual machine
  (6 vCPU of an Intel Core i5-13500T, 7 GiB, NixOS), a hybrid-core CPU shared
  with other guests; frequency scaling is not controllable from the guest.
  Treat sub-millisecond differences as indicative. The paper says so.
- To re-run the exact closure: `nix run ./benchmark#bench` with the committed
  `flake.lock` and manifests. `nix flake metadata ./benchmark --json` prints
  the pinned nixpkgs revision.
