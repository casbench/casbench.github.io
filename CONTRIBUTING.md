# Contributing

Corrections of a task that does not ask a system the way its users would, new
problems, new systems and new checks are welcome: open an issue or a pull
request with the idiom that system's users would write.

A pull request that touches a task file (`E_suite/tasks_<system>.jl`), an
adapter (`lib/adapters/`), a check or a problem list comes with the
contributor's own rows in `docs/disclosures.tsv`: their relation to the systems
compared and to the sources of the problems (author, maintainer, contributor,
employee, funded by, none), and their use of AI assistants (kind
`AI assistance`: for what, how the output was reviewed; naming the tool is
not required), since an
idiom an assistant generated for a system is a possible source of a
benchmark-side error. A row whose project is `none` is also a declaration.
The site renders the file on its conflict of interest page.

Results files under `results/` are produced by the harness only; a pull
request does not edit them by hand. CI checks that `tables/`, `figures/` and
`results/summary.md` are what `make_tables.jl` produces from the committed
results, and that the numbers the site displays match the results files.
