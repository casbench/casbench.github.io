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
F 30 s, G and J 300 s, H 30 s, I 300 s; J uses `BENCH_TIMEOUT_G`) and restarts the
worker at the next case after a timeout or a crash. The subprocess adapters (FriCAS, Maxima, Macaulay2) also run
their system under `timeout`, a safety net for a worker that dies; that limit is 10 s above the case budget, so the
supervisor always stops a case first and records it as a timeout. Choose a new `BENCH_HOST` for a new run: existing result files are never
replaced. `BENCH_RESUME=1` can resume a file only when its header matches the
current format; a legacy file must remain untouched. Results are appended to
`results/<host>/<bench>_<system>.tsv` (one line per case: status, first-call
time, warm time, textual result, note, input, wall time, repeated times, load
average, run id), one directory per host (`BENCH_HOST`, else the hostname);
`results/REFERENCE` names the host whose numbers are published, and
`make_tables.jl` turns that host's files into `tables/*.tex`,
`figures/E_times.tex` and `results/summary.md`. A run on another machine
lands in its own directory and the site compares the hosts.

The optional `A-interfaces` pass extends bench A without replacing its historic
Giac-specific records. It compares the same four expansion inputs through
prebuilt objects, text, persistent subprocesses, and newly started processes,
where each path is available. Its check compares the result numerically with
the input at three fixed points; this is not a proof of equivalence or a check
that the answer is fully expanded. Recordings include the symbolic operation,
conversions and input logging. Persistent subprocess startup is included in
the first call; subsequent warm calls reuse the process. A new-process call
includes startup every time. FriCAS expands polynomial arithmetic as it parses
the input. Repeats use the same expression, so caches and adapter-specific
cache-clearing policies may affect warm timings. Default per-case time limit:
`BENCH_TIMEOUT_A_INTERFACES` (120 s). Different
paths and operations are summarised separately, with verified counts.
Object construction happens before its call is timed and may itself normalise
the expression; text-path calls include construction.

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
harness's own wall time of the minimum-duration measured call (`t_wall_s`, the same
meaning for every system, process start-up included for a system run as one
process per case; `t_warm_s` is the system's own time for those), every
repeated time behind the minimum (`t_repeats_s`), and the 1-minute load
average just before the case (`load_avg`). Files written before 2026-11-20
have ten or eleven columns and no run identity.
Since 2026-11-20 every row also carries an `input` column: what the adapter
sent to the system during the case, in that system's syntax (the strings
evaluated by Giac, the text given to SymPy, the scripts of Maxima, FriCAS,
Sage and Macaulay2; for the Julia-side task files, the arguments). Historical
files truncate the input to 2,000 characters and the output to 200. New
18-column files preserve input, output and check notes in full, using TSV
backslash escapes for backslashes, newlines and tabs. The input is there so that a status can be
checked against the actual command: an unsolved or wrong case may be a command the benchmark
generated wrongly, not a limit of the system.
A case index can appear twice in a file when the supervisor restarted a
worker on it (its timeout record, then the restarted worker's record);
`tools/dedupe_results.py` keeps the last row and CI would show the
difference. `results/history.tsv` keeps one summary row per bench, system and run date
(appended by `make_tables.jl`; `tools/history_backfill.py` rebuilds the past
rows from the git history), from which the site draws its time series.
`results/machine.txt` and `results/environment.txt` record the host, the
Julia and package versions, `versioninfo(verbose=true)`, `lscpu` and the
flake and nixpkgs revisions. To rerun one problem of a suite:
`BENCH_STOP=<idx> julia --project=envs/<system> lib/worker.jl E_suite <system> out.tsv <idx> progress`.

The status vocabulary is the same in every bench: historical `verified` includes
numeric checks; new numeric checks use `verified_numeric` and `verified` is
reserved for exact checks. `wrong` means the check failed, `unverified` (returned, but the check
could not evaluate it), `unsolved` (returned unevaluated or incomplete, or
the system declared that it cannot), `unavailable` (no operation of that kind
in the system, as wired in `lib/adapters/<system>.jl`), `error`, `timeout`.

## Gröbner hard tier and rational parametrizations

The G base tier remains 32 cases. Run `julia run_all.jl G-hard` separately
for cyclic8, cyclic9, katsura10, eco11 and eco12 over Q. Each hard case has
its own supervisor budget: 600 s except cyclic9, which has 3600 s and is a
long-run case. Results are written to separate files. For an interrupted hard
case, the supervisor retains the last checkpointed command or the Julia
arguments if execution had not reached the adapter command. Checkpoint I/O is
excluded from recorded answer times. The parsed, canonical,
reduced basis is checked by reducing the inputs to zero and comparing digests
across systems. This does not establish that every basis element belongs to
the input ideal; matching digests are corroboration, not a proof.

GrobX is driven from a pinned GPL-3.0-only Python wheel, in one thread with a
fixed seed, using the same systems and fields. Rational coefficients in finite
fields are reduced modulo the field prime before the msolve-format instance is
sent. The answering engine's own optional checker is disabled for the timed
call; the common checker above runs afterwards. GrobX's note includes the
peak resident memory of its Python process, including interpreter and imports;
it is not the memory allocated by the engine alone. Base and hard cases use
the same supervisor budgets as the other systems. Historic data are unchanged.
For new G records, `check_wall_s` records elapsed wall time inside the common
Julia checker, including parsing, reduction and any compilation, separately
from answer timings. The existing per-case watchdog still applies while the
check runs; an interrupted check need not yield a check-time record.

J asks for an RUR and real solution isolation on fixed G systems. Its check
substitutes each reported real solution in every input polynomial using
256-bit BigFloat arithmetic, verifies the lifting coordinates, and checks
exact polynomial divisibility of the rational lifting map by the elimination
polynomial, with seeded pseudorandom evaluations of the identity. Separately,
a deterministic Aberth iteration approximates every root of the elimination
polynomial; each complex root is lifted and substituted into every input at
256-bit precision. This numerical method is restricted to squarefree
polynomials of degree at most 96 and 1000 iterations. Root residuals must be
at most `2^-130` times the coefficient-based scale, and roots must be separated
by more than `2^-100` times their magnitude scale. Lifted solution residuals
must be at most `2^-70` times the sum-of-terms scale. Apparent real roots have
imaginary part at most `2^-70` times their magnitude scale; each reported real
solution must match a distinct apparent real root within `2^-50` times its
magnitude scale. These numerical thresholds do not provide a root-isolation
certificate or prove that the reported real list is complete. Nonconvergence,
unsupported separating forms and mismatched apparent real-solution counts are unverified;
Sage/Singular reports non-shape-position systems as unsolved. The J check
has the separate numeric-verification budget (`BENCH_NUMERIC_VERIFY_TIMEOUT`,
60 s by default); if interrupted, the computed answer is retained as
`unverified` and its recorded calculation time remains separate. See the J description in
[Benches](benches.md) for the cases and implementation limits.

## Integration verification

For F and H, six fixed real candidate points in (0, 1) are evaluated at
Float64 precision. The central difference uses `h = 1e-5`; the integrand must
be finite and real at the point and both neighboring points, and at least
four points must be usable. The tolerance is `2e-4 * max(abs(f), 1) + 1e-7`.
The same comparison includes `0.57 + 0.125im` when a conservative local
analyticity screen accepts the integrand with the case's fixed parameters.
It handles arithmetic, integer and principal powers, elementary entire
functions, tangent, hyperbolic tangent, logarithm and square root. At the
sample and its four real- and imaginary-direction neighbours it checks denominators and
branch arguments in Float64, rejecting poles, points near the principal
negative-real cut, non-finite values and unsupported operations. This is not
a rigorous branch certificate; it omits other locally analytic functions.
The chosen point, or its omission, is recorded in the task. At an accepted
complex point, the answer is differentiated in both the real and imaginary
directions. They must agree within `2e-4 * max(abs(d_real), abs(d_imag), 1) + 1e-7`.
If they disagree, the answer is `unverified`: a real-domain expression such as `log(abs(x))` can pass the real check without
being holomorphic. Only a mutually consistent complex derivative that differs
from the integrand is marked `wrong`. Samples and domain checks cannot prove a
global identity or settle branches. H also compares
eligible Lean-certified antiderivatives up to a constant at sampled points.
Numeric evaluation has a separate 60-second supervisor budget, configurable
with `BENCH_NUMERIC_VERIFY_TIMEOUT`. If it is interrupted after an external
system has returned an answer, that answer is retained as `unverified`.

Under the supervisor, symbolic self-verification runs by default after a
numerically verified answer in a separate process, with a 60-second budget.
Set `BENCH_VERIFY_INTEGRALS=0` to disable it and `BENCH_VERIFY_TIMEOUT` to
change the budget. Direct calls to `lib/worker.jl` leave the phase disabled.
The command simplifies `diff(F, x) - f` in the answering system, following
[Xcas chkint.cas](https://github.com/JuliaGiac/giac/blob/99439bb/check/chkint.cas).
The answer times exclude this phase. `verify_status`, `verify_time_s`, and
`verify_input` are appended to new TSV records; input, output, notes and the
verification command escape backslashes, newlines and tabs so they can be reconstructed.
`verified_symbolic` means the system returned exact zero; `verify_unsolved`
and `verify_timeout` do not change the answer's numeric status. Historical
files have no self-check columns. Unintegrable reference cases left unevaluated
are now `unsolved`; older results may classify them as `verified`.

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

## host-2 campaign

`results/host-2/` is the campaign run on a second machine (AMD Ryzen 9
8945HS, 16 threads, 30.6 GiB, a host shared with three virtual machines). It
is the reference host since 2026-11-28 (`results/REFERENCE`): the bench pages,
the tables and the summary give its numbers. `giac-bench`, the Converix virtual
machine of the earlier runs, measured with the checks of their time, stays
published and is compared on the Hosts page.
Every file is copied unchanged from the run that wrote it and named in
`results/host-2/SOURCES.tsv` with its commit and checksum:

- the full campaign at 11b5954, from 2026-11-26 to 2026-11-28: benches A,
  A-interfaces, B, C, D, F, G (base tier), H, I and J for every system, one
  bench per step after ten quiet minutes, with Giac on one thread, the
  numeric check off branch cuts of the integrand and every correction of the
  review of 2026-11-25/26;
- bench E at 6503ecd on 2026-11-28, the suite written for this repository
  (the bench E files of the full campaign measured the earlier suite and are
  not published).

Not included: the hard tier of bench G, whose files hold the full bases (up
to 104 MB a file) and were measured in earlier runs; they are kept with their
checksums in the review archive.

Known limits of these files: Symbolics.jl and SymJ.jl have no evaluation of
`expint`, `expinti`, `sinint`, `cosint`, `sinhint`, `coshint`, `gamma` with two
arguments or `zeta` in their adapters (bench F errors for that reason); bench
F case 444 for Sage/Giac has changed status from run to run. A NixOS build on
the host ran from 21:38:55 to 21:42:15 on 2026-11-27, during bench H for
SymPy: cases 638 to 641 of that file were measured at a load of 6.4 to 6.8
(their `load_avg` column), so their times are indicative; their statuses are
not near a limit.

Both runs were written under the neutral host name (`BENCH_HOST`), so the
files need no renaming: `sha256_as_written` equals `sha256` in `SOURCES.tsv`.
Earlier host-2 files, from the partial campaign of 2026-11-23 to 26, are in
the git history.

## Reproducing on another machine

`BENCH_HOST=<name> nix run .#bench` writes under `results/<name>/`, with that
machine's `machine.txt` and `environment.txt`; `<name>` is also the host
recorded in `machine.txt`, so a neutral name keeps the machine's own name out
of the published files, and `environment.txt` keeps only the `JULIA_*`
variables. Commit the directory and the
site's Hosts page compares every host. Statuses should agree across hosts (a
difference is a bug of the benchmark or an unstable case); times scale with
the machine, which the calibration workload makes comparable.

## Reproducibility notes

- Inputs are never drawn at run time. The semiprimes of bench C were produced
  once by `C_ifactor/generate_inputs.jl` (next prime after fixed starting
  points) and pasted into `inputs.jl`.
- The reported numbers are those of `host-2`, a physical machine (AMD
  Ryzen 9 8945HS, 16 threads, 30.6 GiB, NixOS) that also runs three virtual
  machines; the measured runs waited for ten quiet minutes before each bench.
  Frequency scaling is not controlled. Treat sub-millisecond differences as
  indicative. The earlier reference, `giac-bench`, was a Converix virtual
  machine (6 vCPU of an Intel Core i5-13500T, 7 GiB, NixOS).
- To re-run the exact closure: `nix run .#bench` with the committed
  `flake.lock` and manifests. `nix flake metadata . --json` prints the pinned
  nixpkgs revision.
- CI does not run the benches; it checks that `tables/`, `figures/` and
  `results/summary.md` are what `make_tables.jl` produces from the committed
  results, and tests the site generator.

## Site

`tools/site/build.sh OUT` generates the pages from `results/` with
`tools/site/sitegen.py` and builds them with the pinned Hugo
(`tools/site/install_hugo.sh DIR`), the Hextra theme and the
[site-kit](https://github.com/s-celles/site-kit) module, pinned in
`site/go.mod`; nothing is written inside the repository. The site follows
the site-kit SPEC named in `site-kit.json` (the four project sites share it):
`.github/workflows/site.yml` builds it twice, runs site-kit's
`check_site.py` and `compare_builds.py` at the pinned tag (two builds of one
commit must be identical, so no build time is written), and deploys it to
GitHub Pages. The tables keep this site's own `site/assets/js/tables.js`
(per-column filters, multi-key sorting, CSV export) in place of site-kit's.
Case pages stay out of Hextra's sidebar and search index (`llms-full.txt`
has every case as text): listed in the sidebar of every page, three thousand
cases made each page 3 MB and the site 4 GB.

## Planned

- The per-integral grades of the 12000.org reports as a column of bench F.
- Reduce, which is not in nixpkgs, and Rubi, which needs Mathematica, are the
  two systems of the 12000.org tests not run here.
- giac-wasm, once it is published: the Giac engine compiled to WebAssembly,
  driven through Node.js as the Compute Engine is (`lib/adapters/computeengine.jl`),
  on every bench where Giac.jl runs, so that one engine is compared through
  three paths (Giac.jl, Sage/Giac, giac-wasm). A WebAssembly build may lack
  parts of the native one (threads, the libraries behind integer and
  polynomial factorisation or Gröbner bases); the coverage of bench D and the
  statuses of benches C, G and J will show what it has, rather than an
  assumption.
