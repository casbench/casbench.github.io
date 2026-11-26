# Instructions for agents and contributors

These apply to every change to this repository, whether written by a person
or by an agent on a person's behalf.

## Declare conflicts of interest and AI assistance

Every contributor to the benchmarks declares, in `docs/disclosures.tsv`, their
relation to the systems compared and to the sources of the problems (author,
maintainer, contributor, employee, funded by, none) and their use of AI
assistants (for what, how the output was reviewed; the tool need not be
named). One row per
contributor and project; a row whose project is `none` is also a declaration.
A change that touches a task file (`E_suite/tasks_<system>.jl`), an adapter
(`lib/adapters/`), a check, a problem list or an input file is not complete
without the rows of the person it is made for. An agent making such a change
adds or updates the rows of the person it works for, including their
`AI assistance` row. The site renders the file on its disclosures
page; `tools/site/test_sitegen.py` checks that the file parses and that an
AI assistance row exists. See `CONTRIBUTING.md`.

## Measurements

- Files under `results/<host>/` are written by the harness only
  (`run_all.jl`, `lib/supervise.jl`, `lib/worker.jl`); never edit them by
  hand, never generate a number outside the scripts. A run starts from a
  committed tree (`run_all.jl` refuses a dirty one) so that every record's
  run id and the harness commit in `machine.txt` identify the code.
- `tables/`, `figures/` and `results/summary.md` are what `make_tables.jl`
  produces from the committed results; CI rejects a drift.
- Every number the site displays is computed from `results/*.tsv` at build
  time; `tools/site/sitegen.py` refuses a home page whose counters disagree
  with the data, and the tests recompute them independently.

## Measuring and rerunning

- Measure on a quiet machine, one supervised run at a time: no other
  benchmark, build or test may run on the measuring machine during a
  measurement (a shared host's builds raised the load to 15 and distorted
  times on 2026-11-25). Queues wait for a quiet machine before each step.
- A correction that changes a status is applied by rerunning, never by
  editing or reclassifying a results file: rerun the affected systems from a
  committed tree into a new results directory, with the same inputs and
  budgets for every system compared, and keep the old files.
- A rerun of a few cases starts one case earlier as a warm-up
  (`BENCH_START_INDEX`) for systems with a compiled or persistent process
  (the Julia packages, Sage, the Compute Engine): a cold worker charges its
  start-up to the first case's budget. Only the target cases are results.
- A fix comes with a test that fails before it and passes after it, run on
  the measuring machine when it needs the systems (no Julia on the
  workstation).

## Publishing results

- The reference host (`results/REFERENCE`) gives the numbers of the bench
  pages; another machine's campaign is published as its own host directory,
  `results/<host>/`, and compared on the Hosts page. Changing the reference
  host is the owner's decision.
- A host is published under a neutral name (`BENCH_HOST=host-<n>`), never
  under a personal machine's own hostname, and its files carry no user name,
  home directory or session counters. A campaign already written under
  another name is renamed with `tools/anonymize_host.py`, the only change
  allowed to a results file outside the harness. Only the identity is
  hidden: the machine's characteristics (processor, memory, threads, kernel,
  versions, what shares the host) stay in the files and the texts.
- A campaign assembled from several runs (a main run, then targeted reruns)
  copies each results file unchanged from the run that wrote it, the latest
  run's file replacing an earlier one, with a `SOURCES.tsv` naming for each
  file its run directory, commit, run id and SHA-256; `machine.txt`
  concatenates the machine blocks of the contributing runs in time order, so
  that the history dates each file by its last run.
- A partial campaign says so: `docs/methodology.md` names what it includes,
  what is held back and what pending reruns will change.
- Files over GitHub's limits are not committed and not trimmed: they are
  listed as held back in `SOURCES.tsv` and kept, with their checksums, in the
  review archive (the hard tier of bench G stores full bases, up to 104 MB a
  file).
- After adding results, regenerate `results/history.tsv`,
  `results/summary.md`, `tables/` and `figures/` with `make_tables.jl` (on
  the measuring machine) and commit them with the results; CI rejects a
  drift. Run the site tests (`tools/site/test_sitegen.py`) before pushing;
  they write whole sites to temporary directories, so point `TMPDIR` to a
  disk with room for them.
- Publish by fast-forwarding `main`; the site workflow builds with the full
  git history (its stamps name the last commit that changed `results/`).
  Commit messages: a short imperative subject, a body that says why, no
  trailers.

## Text

- An unsolved or wrong case may be an error of the benchmark (an idiom that
  does not ask a system the way its users would); say so rather than
  blaming the system, and keep the exact input visible next to the output.
- Site, README and documentation texts: no em-dashes.
- Case names in a bench are stable identifiers of the results files; renaming
  one breaks the history of that case.
