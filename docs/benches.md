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
basis, factorisation over the complex numbers (checked at complex points), a
symbolic determinant and eigenvalues, a 60-digit factorisation, and
simplification under an assumption.

**E, a problem suite** (`E_suite/`; same four systems). The 103 problems of
"Giac.jl against Mathematica", the notebook `notebooks/giac_vs_wolfram.jl` of
the `ergonomics` branch of Kahli Burke's fork of Giac.jl
(github.com/kahliburke/Giac.jl, commit da3d2f1a, 2026-11-12), with the problem
statements taken from that notebook (twelve categories: indefinite and
definite integrals, sums and products, limits, equations and inequalities,
polynomial algebra, simplification and algebraic numbers, differential
equations, linear algebra, number theory, transforms and special functions,
control), plus a "model to Jacobian" category in the style of its companion
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
Every answer is verified in plain Julia with the notebook's criteria (value
to a tolerance with exactness required, antiderivative by its derivative at
points, solutions substituted and counted, ODE residuals with the constants
set, regions tested at points, forms). The per-case limit is 60 s.
`make_tables_E.jl` produces the category table (Giac.jl against SymPy:
solved, both solved, faster, median time ratio), the four-system table
(median ratio to the fastest system, answered, fastest) and the dot plot of
every problem's time (`figures/E_times.tex`, pgfplots).

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
arithmetic, SpecialFunctions) at the points x = 0.31, 0.57, 0.83 where the
integrand is real, with every parameter at a fixed value (a = 1.7, b = 0.6,
c = 2.3, d = 1.1, ...). An answer whose real part is the antiderivative (a
form derived on another domain) is verified with the note "real part only".
Entries whose reference is `Unintegrable` are verified when the system
returns the integral unevaluated, as in the 12000.org grading. The note
carries the leaf counts of the answer and of the reference; the grade of
those tests is A when the answer is right and at most twice the size of the
reference, B when right but larger, F otherwise (the C grade, a right answer
of lower quality, is not reproduced). The per-case limit is 30 s (3 min in
the original). For context, the Summer 2024 edition scores Giac/Xcas 1.9.0-99
at 57.5 % and SymPy 1.12 at 42.2 % over all 106 812 integrals; the sample
here is small and the check is different, so the numbers are not comparable
to those, only to each other.

**G, Gröbner bases** (`G_groebner/`; Giac.jl `gbasis`, Groebner.jl, msolve
through AlgebraicSolving.jl, SymPy `groebner`; Singular and Giac through
SageMath, and Macaulay2, as subprocesses). Reduced degrevlex Gröbner
bases of sixteen classical systems of the literature (katsura 5 to 9,
cyclic 4 to 7, eco 7 and 10, noon 4 to 6, henrion 5, chandran 5), whose
strings were generated once with the `Examples` module of Groebner.jl
(GPL-2.0) and stored in `G_groebner/inputs.jl`, each over Q and
over GF(1073741827). The printed basis is parsed and put in canonical form by
`lib/poly.jl` (monic, sorted by leading monomial; a reduced Gröbner basis is
unique, so correct answers have the same canonical form, whose digest is in
the note and whose agreement between systems is in the table); it is checked
to be reduced, and every input polynomial is reduced to zero modulo it by the
division algorithm over a prime field. The per-case limit is 300 s.
Singular.jl does not precompile on Julia 1.13 at the pinned versions and is
not included.

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
from the input. SymEngine.jl (the C++ symengine core) joins here and in
benches B and D, where most of its cells are *unavailable*: it has no
integration, factorisation or solving. A finding of this bench: Symbolics.jl
(7.49, SymbolicUtils 3) expands (x+y+z)^50 with wrong coefficients (the
value at (1,1,1) is 6.33e20 instead of 3^50 = 7.18e23, while degree 20 is
exact), the same defect as SymbolicUtils.jl issue 1195 (`expand` silently
overflows Int64 coefficients of high powers, reported on 2026-11-16 with
(x+y)^70, where Giac.jl and SymJ.jl serve as oracles); the derivative row of
bench I is therefore *wrong* for it until that issue is fixed.

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
are skipped (113 of 1380); 409 usable rules are proved over R and 858 refuted.
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
