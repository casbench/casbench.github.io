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

CASbench now supplies a supervised adapter for version 0.73.3, pinned by the
wheel's SHA-256. It uses the unchanged fixed systems, variable and monomial
order, fields, budgets and independent G check, with a fixed seed and one
thread. Tests cover Q and a prime field, including rational coefficients.
GrobX's optional checker and cofactor certificates are not enabled in the
timed call. GrobX records its process peak RSS, including Python startup; new
G records also report the elapsed time of the common checker separately.
Early records used `getrusage`, which can inherit the launching worker's peak;
their RSS values are not reliable case-level peaks. The corrected Linux runner
reads the current process address space's `VmHWM` instead.
The published GrobX timings cannot be combined directly with CASbench's warm
call timings. No CASbench GrobX result has been committed yet; measurements
must come from our own harness and be reviewed before publication.

The GrobX instance corpus may suggest additional problems, but it must be
reviewed independently for provenance, licence, fixed inputs and coverage
before any instances are incorporated. No external benchmark collection has
been copied into this repository by this note.
