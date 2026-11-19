# Bench F: a fixed sample of Nasser M. Abbasi's independent integration tests
# (12000.org, Summer 2024 edition), drawn by F_integration/sample.jl: three
# entries from each of the 215 test files of the 2023 SymPy-format archive
# (639 integrals, with the optimal antiderivative the test file gives).
#
# Each adapter maps :integrate_text to (integrand::String, var::String) ->
# answer, translating the Maple-like text to its own syntax (lib/mapleish.jl).
#
# Check (plain Julia, system-neutral): the derivative of the answer, by a
# central finite difference computed with the system's own numeric evaluation
# of its answer, equals the integrand evaluated in plain Julia (complex
# arithmetic, SpecialFunctions for erf, Ei, gamma, ...) at three points, with
# every parameter at a fixed value. Entries whose reference is "Unintegrable"
# (the test file says there is no closed form) are verified when the system
# returns the integral unevaluated, as in the 12000.org grading.
#
# The note carries the leaf counts of the answer and of the reference; the
# grade of the 12000.org tests is A when the answer is right and not more
# than twice the size of the reference, B when right but larger, F otherwise
# (their C grade, a right answer of lower quality, is not reproduced).

isdefined(Main, :check_integral) || include(joinpath(@__DIR__, "..", "lib", "integration_check.jl"))

function read_sample()
    rows = NamedTuple[]
    for (i, line) in enumerate(eachline(joinpath(@__DIR__, "sample.tsv")))
        i == 1 && continue
        f = split(line, '\t')
        length(f) == 7 || continue
        push!(rows, (id = parse(Int, f[1]), file = String(f[2]), line = parse(Int, f[3]), integrand = String(f[4]),
                     var = String(f[5]), steps = parse(Int, f[6]), reference = String(f[7])))
    end
    rows
end

const SAMPLE = read_sample()
const PROBLEMS = [(name = "$(r.id) " * replace(r.file, r"\.txt$" => "") * ":" * string(r.line) * " " * first(r.integrand, 60),
                   op = :integrate_text, args = V -> (r.integrand, r.var, FPARAMS),
                   check = o -> check_integral(o, r.integrand, r.reference),
                   note = "int " * first(r.integrand, 120) * " dx; reference " * first(r.reference, 100),
                   accept_unsolved = occursin("Unintegrable", r.reference) || occursin("CannotIntegrate", r.reference))
                  for r in SAMPLE]
