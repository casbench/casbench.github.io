# The benches

What each bench measures, its inputs and its checks. The harness, the adapters and the status vocabulary are in [methodology.md](methodology.md).

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

**A, interface paths** (`A_interfaces/`, run separately as `A-interfaces`).
The same four small polynomial expansions are sent to Giac.jl, Symbolics.jl,
SymPy via PythonCall, SymJ.jl, SymEngine.jl, Maxima and FriCAS. For Julia
packages, the operations distinguish prebuilt symbolic objects from text
parsed for each call. For Maxima and FriCAS they distinguish a persistent
process from a newly launched process for every call. Unsupported paths are
`unavailable`, not zero-cost measurements. FriCAS normalises polynomial
arithmetic while parsing rather than using a separate polynomial expansion
command. The paths include the operation itself, conversions, and any input
logging, so these are call latencies, not an isolated measurement of FFI
overhead. The outputs are checked numerically at three fixed points; this does
not prove symbolic equality or that the result is fully expanded. The ordinary
supervisor records the first call and repeated warm-call measurements; the
first persistent-process call includes startup and later calls reuse it.
Repeated calls use the same input, so system caches and adapter-specific
cache-clearing policies may affect warm timings. Some systems normalise an
object during its construction, which occurs before the object-path timer;
the text path includes construction, so the paths need not perform equal work.
The other benchmarks and the historical A results are unchanged.

**B, CAS operations** (`B_cas/problems.jl`; Giac.jl, Symbolics.jl, SymPy, SymEngine.jl,
SymJ.jl). `expand`, `factor`, `integrate` and `simplify` on 34 fixed inputs.
Returned answers are checked as well as timed: expansion by numeric equality with
the input at three fixed points and the expected number of terms;
factorisation by the product of the returned factors and the number of
irreducible factors over the rationals; integration by a central finite
difference of the antiderivative against the integrand at three points;
simplification by numeric equality without a required printed form. Historical
results used a printed-size bound. Two
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

**D, functional coverage** (`D_coverage/problems.jl`; same five systems). One
problem per capability, starting with the three headline problems of the
JuliaCon 2026 talk (`factor(x^4-1)`, `solve(cos(x)=1/2)` exactly,
`21u+28v=7` over the integers), then Laplace and Z transforms, partial
fractions, an initial value problem, limits, series, closed-form sums, a
non-elementary integral, polynomial gcd, resultant, discriminant, a Groebner
basis, factorisation over the complex numbers (checked at complex points), a
symbolic determinant and eigenvalues, a 60-digit factorisation, and
simplification under an assumption.

**E, a problem suite** (`E_suite/`; Giac.jl, Symbolics.jl, SymPy and SymJ.jl). The 103 problems of
"Giac.jl against Mathematica", the notebook `notebooks/giac_vs_wolfram.jl` of
the `ergonomics` branch of Kahli Burke's fork of Giac.jl
(github.com/kahliburke/Giac.jl, commit da3d2f1a, 2026-11-12), with the problem
statements taken from that notebook (twelve categories: indefinite and
definite integrals, sums and products, limits, equations and inequalities,
polynomial algebra, simplification and algebraic numbers, differential
equations, linear algebra, number theory, transforms and special functions,
control), plus seven identity-difference and nonzero control cases, and a "model to
Jacobian" category in the style of its companion
`notebooks/cas_comparison.jl` (the Brusselator ring, N = 10 and 50: the
Jacobian compiled to a function, then evaluated at 1000 points). Mathematica
is not run; the Giac.jl measured is the released package without the fork's
Julia-side layers (where Giac has no command the tasks call PARI through
Giac's `pari` command, as the notebook does; where nothing exists the task is
`missing`). Each system implements the tasks idiomatically in
`E_suite/tasks_<system>.jl`; two idioms are applied alike to Giac and SymPy:
improper integrals use Giac's signed `+infinity` (the unsigned `infinity`
leaves a definite integral unevaluated), and the two infinite products, which
neither evaluates as such, are asked as the limit of the partial product.
Returned answers are checked in plain Julia using criteria from the notebook (value
to a tolerance with exactness required, antiderivative by its derivative at
points, solutions substituted and counted, ODE residuals with the constants
set, and regions tested at points). Identity differences require an explicit
zero and a high-precision numeric check; controls use certified intervals.
The per-case limit is 60 s. `make_tables_E.jl` produces coverage tables and
a dot plot of individual case times (`figures/E_times.tex`, pgfplots).

**F, integration sample** (`F_integration/`; Giac.jl, Symbolics.jl and
SymJ.jl through RischIntegrate.jl, SymPy; Maxima and FriCAS as subprocesses;
SageMath driving Giac, Maxima, FriCAS and SymPy, the configuration of the
12000.org tests for the first three). A fixed sample of Nasser M.
Abbasi's independent integration tests (12000.org, Summer 2024 edition,
106 812 integrals from the Rubi test suite and other collections): three
entries from each of the 215 test files of the 2023 SymPy-format archive,
639 integrals, drawn once by `F_integration/sample.jl` with a fixed generator
and committed as `F_integration/sample.tsv` (file, line, integrand, variable,
Rubi's step count and the optimal antiderivative the file gives). The
Maple-like text of the files is translated to each system's syntax by
`lib/mapleish.jl`. Every answer is checked in plain Julia: the derivative of
the answer, by a central finite difference of the system's own numeric
evaluation of its answer, against the integrand evaluated in Julia (complex
arithmetic, SpecialFunctions) at six candidate real points. At least four
must be usable. A complex point is also checked when a conservative local screen accepts
the integrand after checking supported operations, poles and principal branch
cuts at the finite-difference stencil. If the answer's real- and
imaginary-direction differences disagree, it is unverified, since a
real-domain antiderivative need not be holomorphic. The separate symbolic phase asks the
answering system to simplify the derivative residual to zero. The note carries
sampled numeric values and leaf counts; the per-case answer limit is 30 s.
For historical runs the method and status meanings differ; see Methodology.

Maple's multi-argument `Zeta(0, s, a)` (the Hurwitz zeta function) and
`Ei(n, z)` (the generalized exponential integral E_n) are translated by arity
(since 2026-11-26; before, they reached every system with Maple's arguments
and were rejected or misread, cases 616, 617 and 628 to 630): SymPy `zeta(s, a)`
and `expint(n, z)`, Sage `hurwitz_zeta` and `exp_integral_e`, Maxima
`expintegral_e`, Giac `Ei(z, n)`, and the Julia check `zeta(s, a)` and
`expint(n, z)`, each checked numerically in the system. Giac (whose
two-argument `Zeta` is another function), Maxima and FriCAS have no Hurwitz
zeta function and FriCAS no E_n: for them the case is an error "unsupported
function ... no translation for this system", like the abstract functions `g`
and `Derivative`. When FriCAS (directly or through Sage) returns a list of
antiderivatives, one per case of a parameter's sign, each form is evaluated
and checked at the fixed parameter values: the case is verified when one form
verifies, wrong when every form fails (since 2026-11-26; before, a list could
not be evaluated and was unverified).

**G, Gröbner bases** (`G_groebner/`; Giac.jl `gbasis`, Groebner.jl, msolve
through AlgebraicSolving.jl, SymPy `groebner`; Singular and Giac through
SageMath, Macaulay2 and GrobX 0.73.3, as subprocesses). GrobX is GPL-3.0-only;
its pinned Python wheel is supplied by the Nix environment. Reduced degrevlex Gröbner
bases of sixteen classical systems of the literature (katsura 5 to 9,
cyclic 4 to 7, eco 7 and 10, noon 4 to 6, henrion 5, chandran 5), whose
strings were generated once with the `Examples` module of Groebner.jl
(GPL-2.0) and stored in `G_groebner/inputs.jl`, each over Q and
over GF(1073741827). The printed basis is parsed and put in canonical form by
`lib/poly.jl` (monic, sorted by leading monomial; a reduced Gröbner basis is
unique, so correct answers have the same canonical form, whose digest is in
the note and whose agreement between systems is in the table); it is checked
to be reduced, and every input polynomial is reduced to zero modulo it by the
division algorithm over a prime field. This does not prove that each basis
element belongs to the input ideal or independently check all S-polynomials;
digest agreement is corroborating evidence, not a proof. The per-case limit
is 300 s for the base tier. Giac runs on one thread in every column, Giac.jl
and Sage/Giac alike (`threads:=1`, set at load and after each `restart`, and
in the Sage script before the timed call): by default its `gbasis` over Q
reconstructs in parallel (15 threads on the 16-thread `host-2`), while every
other system runs on one thread. Runs before 2026-11-26 used Giac's default. A separate `G-hard` pass adds cyclic8,
cyclic9, katsura10, eco11 and eco12 over Q. The individual budgets are
600 s, except cyclic9 (3600 s, long-run). Its fixed inputs are generated by
`tools/groebner/generate_hard.jl` from the pinned Groebner.jl Examples module;
the base records and their case indices stay unchanged. Hard-tier records use
the operation label `groebner_hard` so their timing statistics stay separate
from the base tier. A timeout is an observation at that case's budget.
Singular.jl does not precompile on Julia 1.13 at the pinned versions and is
not included.

GrobX receives the same inputs in msolve text format, with one thread and a
fixed seed. For finite fields, rational coefficients are reduced modulo the
same prime before sending them. Its own optional checker is disabled for the
timed call; the common independent G check is applied afterwards. First-call
time includes Python startup; warm time is GrobX's in-process call time. GrobX
records the Python process peak resident memory in its case note, including
interpreter startup and imports. This is a process-level metric, not an engine
allocation count, and is not directly comparable to an unrecorded peak for
another system. On Linux it uses `VmHWM` for the current process address space;
the earlier `getrusage` measurement can inherit the launching worker's peak
and must not be treated as an independent case-level peak. Basis length, maximum degree and term count are also recorded
by the common checker. No GrobX reference results have been committed yet.
For newly recorded G cases, `check_wall_s` is the wall time of the common
Julia checker, including parsing, reduction and any compilation. It is recorded
separately from the answer time, but remains subject to the case watchdog;
an interrupted check may have no complete check-time record.
Use `BENCH_G_SYSTEMS=grobx` with `nix run .#bench -- G G-hard` to run only
GrobX; the same selection applies to both tiers without changing their inputs.

**J, rational univariate representations** (`J_rur/`; Giac.jl, msolve through
AlgebraicSolving.jl and Singular through SageMath). It reuses the fixed
katsura5, cyclic5, eco7 and noon5 systems from G. The operation computes a
rational parametrization and isolates real solutions: msolve and Sage/Singular
request 256-bit precision; Giac refines intervals to 10^-80 and evaluates
them to 100 decimal digits. In plain Julia, the checker substitutes every
reported real solution at 256-bit precision. It independently approximates
all complex roots of the elimination polynomial with deterministic Aberth
iteration, lifts each root through the returned map and substitutes it into
the input polynomials at 256-bit precision. The checker also verifies the
lifting identities modulo the elimination polynomial using exact rational
arithmetic and seeded pseudorandom evaluations. The numerical root method is
limited to squarefree polynomials of degree at most 96 and 1000 iterations;
failed convergence, a singular denominator, an unsupported separating form, or a mismatch in the apparent number of real
solutions is `unverified`. Approximation is not a
root-isolation certificate, and these checks do not prove completeness of the
reported real solution list or equality of ideals. The verification phase has
a separate 60-second default limit; an interrupted check retains the computed
answer as unverified.
The Sage/Singular adapter requires the last input variable to be separating;
otherwise it reports `unsolved` rather than attempting a change of variables.

**I, throughput at scale** (`I_scale/`; Giac.jl, Symbolics.jl, SymEngine.jl,
SymJ.jl, SymPy). Where B and E time small expressions, this bench asks how
the time grows with the size of the expression, on fixed workloads: dense
expansion of (x+y+z+w)^n for n = 8, 16, 24, 32; the derivative of the
1 326-term expansion of (x^y+y^z+z^x)^50; the Taylor polynomial of order 15
of sin(cos(1+x)); substitution of one symbol (a rule that touches every
occurrence) and numeric evaluation on random expression trees of a
thousand, ten thousand and a hundred thousand leaves; and code generation
(the tree compiled to a function, then a thousand calls, whose time is the
warm time while the first-call time includes the compilation). The trees
come from a deterministic generator in `I_scale/inputs.jl` (a fixed
congruential generator, a given seed), printed in the Maple-like syntax for
the systems and evaluated in plain Julia for the check: the number of terms
of an expansion must be the expected one and the value of every answer at a
point, by the system's own numeric evaluation, must equal the value computed
from the input. The CortexJS Compute Engine (a JavaScript engine working on
MathJSON, driven through Node.js, `lib/adapters/computeengine.jl`) joins
benches F, H and I: the Maple-like text becomes MathJSON, the answer comes
back as LaTeX with the numeric values the check needs. SymEngine.jl (the C++
symengine core) joins here and in benches B and D, where most of its cells are *unavailable*: it has no
integration, factorisation or solving. The case pages show the individual
inputs, outputs and checks, including links to the measured data.

**H, OSR rules** (`H_osr/`; the systems of bench F). The integration rules
of [OpenSymbolicRules](https://opensymbolicrules.github.io/) v1
(`osr/Integration/v1/integration.osr.json`, OpenMath 2.0 JSON, pinned as a
git submodule), converted once by `H_osr/convert.py` into `H_osr/rules.tsv`:
the integrand of each rule's pattern in the Maple-like syntax of bench F, the
certified replacement as a Julia expression (residual integrals
`int(lambda t. H)(x)` become numeric quadratures), the conditions as a Julia
boolean, and the Lean verdicts over R and C. Each rule is a problem: its
parameters take the first set of fixed values that satisfies its conditions
(integers where the rule asks for integers), every system integrates the
integrand, the answer is checked by differentiation as in bench F, and for a
rule proved over R it is also compared with the certified replacement up to a
constant (the note says `certified: agree` or `certified: differ`). Rules
whose variable names are not among the parameter symbols the adapters know
are skipped. The source records which rules are proved or refuted.
Verdict semantics, as OSR states them: "proved over R / C" is a Lean proof
that the rule as stated holds in the OSR fragment; "refuted over R" is a Lean
counterexample to the rule as stated in that fragment (where `ln` is defined
on the positive reals only, `power` interprets integer exponents only and
the conditions are exactly those listed), usually a domain subtlety such as
ln x against ln |x|, a degenerate coefficient or a pole, not a wrong Rubi
table entry; "unproved" is neither. The check never uses a refuted
replacement, and a proof is a statement about the rule, not about any CAS.
The v1 format is a pilot (`osr_format` 1.0.0-alpha.1, no tags yet): the
commit and the Verification report digest are recorded in the header of
`rules.tsv`. Citation: OpenSymbolicRules (OSR) v1,
https://opensymbolicrules.github.io/, rule set
https://github.com/OpenSymbolicRules/Integration (pinned commit in
`.gitmodules`), suites https://github.com/OpenSymbolicRules/Conformance.
OSR lists these benchmarks on its "Used by" page.
