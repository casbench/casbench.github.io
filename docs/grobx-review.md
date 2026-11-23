# GrobX and its benchmark suite

[GrobX](https://github.com/code1-de/grobx) is a Gröbner basis implementation
published by Code1 GmbH under GPL-3.0-only, also offered under commercial
licence. Its public Python interface and command-line program accept the
msolve text format and compute reduced bases over prime fields and over Q.
The project's [package documentation](https://pypi.org/project/grobx/0.73.3/)
describes the version, interface, parameters and licence.

The [GrobX benchmark page](https://grobx.com/benchmarks.html) presents field,
thread, time and memory selections, per-family filters, and relative times.
It describes whole-call timings including parsing and formatting, a geometric
mean over repeated runs after subtraction of a trivial-call cost, sampled
memory peaks, timeout penalties, and eligibility rules for comparisons. It
also distinguishes levels of certainty for rational bases. These are the
publisher's methods and claims, not independent CASbench measurements.

For a CASbench comparison, add an adapter under the existing supervisor, pin
the executable and its dependencies, and capture the exact version and
command. Use our unchanged fixed systems, variable and monomial order, fields,
per-case budgets, single-thread policy and independent basis check. Record
any GrobX checker or cofactor certification separately, including its time.
Test the parsing and conventions over both Q and a prime field before a run.
The published GrobX timings cannot be combined directly with CASbench's warm
call timings; any new measurements must come from our own harness.

The GrobX instance corpus may suggest additional problems, but it must be
reviewed independently for provenance, licence, fixed inputs and coverage
before any instances are incorporated. No external benchmark collection has
been copied into this repository by this note.
