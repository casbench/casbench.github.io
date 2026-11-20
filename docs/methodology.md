# Methodology

How a run is made and checked; the benches themselves are described in [benches.md](benches.md).

## Running the benches

Clone with `git clone --recurse-submodules` (or run `git submodule update
--init` once): the Giac environments point at `Giac.jl/` by path
(`../../Giac.jl`), so that the exact commit measured is part of the pin.

```sh
nix run .#bench            # every bench, then the tables
nix run .#bench -- A C     # a subset
```

Without Nix: `julia --startup-file=no run_all.jl` with Julia 1.13, a Python 3
interpreter that can `import sympy` (set `JULIA_PYTHONCALL_EXE` to it and
`JULIA_CONDAPKG_BACKEND=Null`, otherwise CondaPkg installs its own), and
network access for `Pkg.instantiate`.

Every bench/system pair runs in its own Julia process with one thread, from
its own environment under `envs/`, under `lib/supervise.jl`, which enforces a
per-case time limit (`BENCH_TIMEOUT_<bench>`, read by `run_all.jl`; defaults B 120 s, C 600 s, D 120 s, E 60 s,
F 30 s, G 300 s, H 30 s, I 300 s) and restarts the
worker at the next case after a timeout or a crash. Results are appended to
`results/<host>/<bench>_<system>.tsv` (one line per case: status, first-call
time, warm time, textual result, note, input, wall time, repeated times, load
average, run id), one directory per host (`BENCH_HOST`, else the hostname);
`results/REFERENCE` names the host whose numbers are published, and
`make_tables.jl` turns that host's files into `tables/*.tex`,
`figures/E_times.tex` and `results/summary.md`. A run on another machine
lands in its own directory and the site compares the hosts.

## Run identity and noise

A run must be identifiable. `run_all.jl` refuses to start from a working
tree with uncommitted changes outside `results/` (set `BENCH_ALLOW_DIRTY=1`
to run anyway: the run id then ends in `-dirty`). Every block of
`results/<host>/machine.txt` records the run id (`<date>_<host>`), the
commit of the harness, whether the tree was dirty, the commits of the
`Giac.jl` and `osr/Integration` submodules, the load average and the time of
a calibration workload (two hundred million square roots in plain Julia, the
minimum of three runs, `calibration_s`): a scale to compare machines and a
detector of a perturbed run. Every record carries the run id (`run`), the
harness's own wall time of the fastest measured call (`t_wall_s`, the same
meaning for every system, process start-up included for a system run as one
process per case; `t_warm_s` is the system's own time for those), every
repeated time behind the minimum (`t_repeats_s`), and the 1-minute load
average just before the case (`load_avg`). Files written before 2026-11-20
have ten or eleven columns and no run identity.
Since 2026-11-20 every row also carries an `input` column: what the adapter
sent to the system during the case, in that system's syntax (the strings
evaluated by Giac, the text given to SymPy, the scripts of Maxima, FriCAS,
Sage and Macaulay2; for the Julia-side task files, the arguments), truncated
to 2 000 characters. It is there so that a status can be checked against the
exact input: an unsolved or wrong case may be a command the benchmark
generated wrongly, not a limit of the system.
`results/history.tsv` keeps one summary row per bench, system and run date
(appended by `make_tables.jl`; `tools/history_backfill.py` rebuilds the past
rows from the git history), from which the site draws its time series.
`results/machine.txt` and `results/environment.txt` record the host, the
Julia and package versions, `versioninfo(verbose=true)`, `lscpu` and the
flake and nixpkgs revisions. To rerun one problem of a suite:
`BENCH_STOP=<idx> julia --project=envs/<system> lib/worker.jl E_suite <system> out.tsv <idx> progress`.

The status vocabulary is the same in every bench: `verified` (returned and
checked), `wrong` (the check failed), `unverified` (returned, but the check
could not evaluate it), `unsolved` (returned unevaluated or incomplete, or
the system declared that it cannot), `unavailable` (no operation of that kind
in the system, as wired in `lib/adapters/<system>.jl`), `error`, `timeout`.

## Adapters

`lib/adapters/{giac,symbolics,sympy,symj,symengine,groebner,msolve}.jl` define the same
small interface (`OPS`, `EVAL`, `NTERMS`, `NFACTORS`, `UNSOLVED`, `VERSIONS`).
The subprocess adapters (`maxima`, `fricas`, `sage_<engine>`, `macaulay2`;
`computeengine` keeps one Node.js process per worker) start one process per case, with a script that prints the answer, the
system's own wall time of the call (reported as the warm time; the first-call
time includes the start-up) and, for bench F, the numeric values of the
answer at the check points, so that the generic check applies unchanged.
These systems come from nixpkgs (`flake.nix`). The Sage columns measure an
engine *through Sage's interfaces*, which is what the 12000.org tests did for
Giac, Maxima and FriCAS, and the interface shows: Sage's pexpect interface to
giac cannot read an answer that giac prints with a warning (reported as an
error), and a question Maxima asks (the sign of a parameter combination) is
an exception in Sage, where the standalone Maxima column answers it from the
fixed values (`lib/adapters/maxima.jl`, the `retrieve` oracle). Sage runs as
one process per worker (`lib/adapters/sage_server.py`). Their
structure follows the worker files of SymJ.jl's `bench/cas` comparison (MIT),
which pair Symbolics.jl and SymJ.jl with GruntzLimit.jl for limits and
RischIntegrate.jl for integrals, since neither has symbolic integration or
limits of its own. Symbolics.jl's polynomial factorisation goes through its
Nemo extension (`factor_use_nemo`); an operation an adapter maps to `missing`
is reported as `unavailable`. SymJ.jl is not in the General registry at the
time of writing and is pinned by URL and tree hash in `envs/symj`.

## Reproducing on another machine

`BENCH_HOST=<name> nix run .#bench` writes under `results/<name>/`, with that
machine's `machine.txt` and `environment.txt`; commit the directory and the
site's Hosts page compares every host. Statuses should agree across hosts (a
difference is a bug of the benchmark or an unstable case); times scale with
the machine, which the calibration workload makes comparable.

## Reproducibility notes

- Inputs are never drawn at run time. The semiprimes of bench C were produced
  once by `C_ifactor/generate_inputs.jl` (next prime after fixed starting
  points) and pasted into `inputs.jl`.
- The reported numbers were obtained on a Converix virtual machine
  (6 vCPU of an Intel Core i5-13500T, 7 GiB, NixOS), a hybrid-core CPU shared
  with other guests; frequency scaling is not controllable from the guest.
  Treat sub-millisecond differences as indicative.
- To re-run the exact closure: `nix run .#bench` with the committed
  `flake.lock` and manifests. `nix flake metadata . --json` prints the pinned
  nixpkgs revision.
- CI does not run the benches; it checks that `tables/`, `figures/` and
  `results/summary.md` are what `make_tables.jl` produces from the committed
  results, and tests the site generator.

## Site

`tools/site/build.sh OUT` generates the pages from `results/` with
`tools/site/sitegen.py` and builds them with the pinned Hugo
(`tools/site/install_hugo.sh DIR`) and the Hextra theme; nothing is written
inside the repository. `.github/workflows/site.yml` deploys it to GitHub Pages.

## Planned

- The per-integral grades of the 12000.org reports as a column of bench F.
- Reduce, which is not in nixpkgs, and Rubi, which needs Mathematica, are the
  two systems of the 12000.org tests not run here.
