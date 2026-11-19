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

using .BenchCommon: numeq
isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "lib", "mapleish.jl"))
using .Mapleish

# fixed values of the parameters; x takes three positive points
const FPARAMS = Dict(:a => 1.7, :b => 0.6, :c => 2.3, :d => 1.1, :e => 0.7, :f => 1.3, :g => 0.9, :h => 1.9, :m => 2.5,
                     :n => 1.5, :p => 0.8, :q => 1.2, :r => 2.1, :s => 1.9, :k => 2.0, :j => 0.35, :i => 0.65,
                     :A => 1.4, :B => 0.9, :C => 2.2, :D => 0.5, :F => 1.6)
const FPOINTS = (0.31, 0.57, 0.83)   # inside (0, 1): asin, sqrt(1 - x^2) and the like stay real
const FNAMES = Symbol[:x; sort!(collect(keys(FPARAMS)); by = string)]

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

unevaluated(out) = (s = string(out); occursin(r"integrate\(|Integral\(|∫|Integral\b|integral\(", s))

function check_integral(out, integrand::String, reference::String)
    s = string(out)
    leaves = leaf_count(s); ref = leaf_count(reference)
    grade_note(st) = (g = st == :verified ? (leaves <= 2ref ? "A" : "B") : "F"; "grade=$g leaves=$leaves ref=$ref")
    if occursin("Unintegrable", reference) || occursin("CannotIntegrate", reference)
        return unevaluated(s) ? (:verified, "reference has no closed form; returned unevaluated, as the reference; " * grade_note(:verified)) :
                                (:unverified, "reference has no closed form but an answer was returned; not checked; leaves=$leaves")
    end
    fev = try
        make_evaluator(integrand, FNAMES)
    catch err
        return (:unverified, "integrand not evaluable in plain Julia: " * first(sprint(showerror, err), 80))
    end
    h = 1e-5
    npts = 0
    realonly = false
    for x0 in FPOINTS
        pt = Dict{Symbol,Float64}(FPARAMS); pt[:x] = x0
        fx = try fev(pt) catch err; nothing end
        (fx === nothing || !isfinite(fx)) && continue
        abs(imag(fx)) > 1e-9 * max(abs(fx), 1.0) && continue      # only points where the integrand is real
        fx = real(fx)
        ptp = copy(pt); ptp[:x] = x0 + h
        ptm = copy(pt); ptm[:x] = x0 - h
        Fp, Fm = EVAL(out, ptp), EVAL(out, ptm)
        (Fp === nothing || Fm === nothing) && continue
        dF = (Fp - Fm) / (2h)
        (isfinite(abs(dF)) && isfinite(abs(fx))) || continue
        npts += 1
        tol = 2e-4 * max(abs(fx), 1.0) + 1e-7     # a central difference of a long printed answer loses a few digits
        if abs(dF - fx) > tol
            # an answer derived on another domain can carry a non-constant imaginary part on this one;
            # its real part is then the antiderivative (sqrt(1 - sqrt(x + 1)) and the like)
            abs(real(dF) - fx) <= tol || return (:wrong, "derivative mismatch at x=$x0: F'=$(round(dF; sigdigits=6)) f=$(round(fx; sigdigits=6)); " * grade_note(:wrong))
            realonly = true
        end
    end
    npts >= 2 || return (:unverified, "fewer than two points could be evaluated; leaves=$leaves ref=$ref")
    (:verified, grade_note(:verified) * (realonly ? "; real part only" : ""))
end

const SAMPLE = read_sample()
const PROBLEMS = [(name = "$(r.id) " * replace(r.file, r"\.txt$" => "") * ":" * string(r.line) * " " * first(r.integrand, 60),
                   op = :integrate_text, args = V -> (r.integrand, r.var),
                   check = o -> check_integral(o, r.integrand, r.reference),
                   note = "int " * first(r.integrand, 120) * " dx; reference " * first(r.reference, 100),
                   accept_unsolved = occursin("Unintegrable", r.reference) || occursin("CannotIntegrate", r.reference))
                  for r in SAMPLE]
