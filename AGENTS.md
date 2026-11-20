# Instructions for agents and contributors

These apply to every change to this repository, whether written by a person
or by an agent on a person's behalf.

## Declare conflicts of interest and AI assistance

Every contributor to the benchmarks declares, in `docs/disclosures.tsv`, their
relation to the systems compared and to the sources of the problems (author,
maintainer, contributor, employee, funded by, none) and their use of AI
assistants (which tool, for what, how the output was reviewed). One row per
contributor and project; a row whose project is `none` is also a declaration.
A change that touches a task file (`E_suite/tasks_<system>.jl`), an adapter
(`lib/adapters/`), a check, a problem list or an input file is not complete
without the rows of the person it is made for. An agent making such a change
adds or updates the rows of the person it works for and names itself in their
`AI assistance` row. The site renders the file on its conflict of interest
page; `tools/site/test_sitegen.py` checks that the file parses and that an
AI assistance row exists. See `CONTRIBUTING.md`.

## Measurements

- Files under `results/` are written by the harness only (`run_all.jl`,
  `lib/supervise.jl`, `lib/worker.jl`); never edit them by hand, never
  generate a number outside the scripts.
- `tables/`, `figures/` and `results/summary.md` are what `make_tables.jl`
  produces from the committed results; CI rejects a drift.
- Every number the site displays is computed from `results/*.tsv` at build
  time; `tools/site/sitegen.py` refuses a home page whose counters disagree
  with the data, and the tests recompute them independently.

## Text

- An unsolved or wrong case may be an error of the benchmark (an idiom that
  does not ask a system the way its users would); say so rather than
  blaming the system, and keep the exact input visible next to the output.
- Site, README and documentation texts: no em-dashes.
- Case names in a bench are stable identifiers of the results files; renaming
  one breaks the history of that case.
