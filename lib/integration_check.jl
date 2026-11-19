# The check shared by benches F and H: the derivative of an antiderivative
# returned by a system, by a central finite difference of the system's own
# numeric evaluation of its answer, against the integrand evaluated in plain
# Julia (complex arithmetic, SpecialFunctions) at three points where the
# integrand is real, with the parameters at fixed values. Optionally, the
# answer is compared with a certified antiderivative up to a constant.

using .BenchCommon: numeq
isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "mapleish.jl"))
using .Mapleish

# fixed values of the parameters (bench F); bench H chooses per rule among candidate sets
const FPARAMS = Dict(:a => 1.7, :b => 0.6, :c => 2.3, :d => 1.1, :e => 0.7, :f => 1.3, :g => 0.9, :h => 1.9, :m => 2.5,
                     :n => 1.5, :p => 0.8, :q => 1.2, :r => 2.1, :s => 1.9, :k => 2.0, :j => 0.35, :i => 0.65,
                     :A => 1.4, :B => 0.9, :C => 2.2, :D => 0.5, :F => 1.6)
const FPOINTS = (0.31, 0.57, 0.83)   # inside (0, 1): asin, sqrt(1 - x^2) and the like stay real
const FNAMES = Symbol[:x; sort!(collect(keys(FPARAMS)); by = string)]

unevaluated(out) = (s = string(out); occursin(r"integrate\(|Integral\(|∫|Integral\b|integral\(", s))

"""
    check_integral(out, integrand, reference; params = FPARAMS, certified = nothing)

Status and note for the answer `out` of a system to `∫ integrand dx`.
`reference` is the antiderivative the source gives (for the leaf-count grade;
"Unintegrable" means no closed form); `certified`, when given, is a Julia
expression text of a proved antiderivative (bench H), compared with the answer
up to a constant at the check points.
"""
function check_integral(out, integrand::String, reference::String; params::Dict{Symbol,Float64} = FPARAMS, certified = nothing)
    s = string(out)
    leaves = leaf_count(s); ref = leaf_count(reference)
    grade_note(st) = isempty(reference) ? "leaves=$leaves" : (g = st == :verified ? (leaves <= 2ref ? "A" : "B") : "F"; "grade=$g leaves=$leaves ref=$ref")
    if occursin("Unintegrable", reference) || occursin("CannotIntegrate", reference)
        return unevaluated(s) ? (:verified, "reference has no closed form; returned unevaluated, as the reference; " * grade_note(:verified)) :
                                (:unverified, "reference has no closed form but an answer was returned; not checked; leaves=$leaves")
    end
    names = Symbol[:x; sort!(collect(keys(params)); by = string)]
    fev = try
        make_evaluator(integrand, names)
    catch err
        return (:unverified, "integrand not evaluable in plain Julia: " * first(sprint(showerror, err), 80))
    end
    cev = certified === nothing ? nothing : (try make_evaluator(certified, names) catch err; nothing end)
    h = 1e-5
    npts = 0
    realonly = false
    Fvals = Tuple{Float64,ComplexF64}[]      # (x0, F(x0)) for the comparison with the certified antiderivative
    for x0 in FPOINTS
        pt = Dict{Symbol,Float64}(params); pt[:x] = x0
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
        F0 = EVAL(out, pt)
        F0 === nothing || push!(Fvals, (x0, ComplexF64(F0)))
    end
    npts >= 2 || return (:unverified, "fewer than two points could be evaluated; leaves=$leaves ref=$ref")
    note = grade_note(:verified) * (realonly ? "; real part only" : "")
    if cev !== nothing && length(Fvals) >= 2
        agree = true
        x1, F1 = Fvals[1]
        pt1 = Dict{Symbol,Float64}(params); pt1[:x] = x1
        R1 = try cev(pt1) catch err; nothing end
        if R1 === nothing || !isfinite(R1)
            note *= "; certified: not evaluable"
        else
            for (xi, Fi) in Fvals[2:end]
                pti = Dict{Symbol,Float64}(params); pti[:x] = xi
                Ri = try cev(pti) catch err; nothing end
                (Ri === nothing || !isfinite(Ri)) && (agree = false; break)
                dF, dR = Fi - F1, Ri - R1
                abs(real(dF) - real(dR)) <= 1e-4 * max(abs(dR), 1.0) + 1e-6 || (agree = false; break)
            end
            note *= agree ? "; certified: agree" : "; certified: differ"
        end
    end
    (:verified, note)
end
