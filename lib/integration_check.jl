# The check shared by benches F and H: the derivative of an antiderivative
# returned by a system, by a central finite difference of the system's own
# numeric evaluation of its answer, against the integrand evaluated in plain
# Julia (complex arithmetic, SpecialFunctions) at six candidate real points,
# with the parameters at fixed values; at least four usable points are required. Optionally, the
# answer is compared with a certified antiderivative up to a constant.

using .BenchCommon: numeq
isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "mapleish.jl"))
using .Mapleish

# fixed values of the parameters (bench F); bench H chooses per rule among candidate sets
const FPARAMS = Dict(:a => 1.7, :b => 0.6, :c => 2.3, :d => 1.1, :e => 0.7, :f => 1.3, :g => 0.9, :h => 1.9, :m => 2.5,
                     :n => 1.5, :p => 0.8, :q => 1.2, :r => 2.1, :s => 1.9, :k => 2.0, :j => 0.35, :i => 0.65,
                     :A => 1.4, :B => 0.9, :C => 2.2, :D => 0.5, :F => 1.6)
# Fixed candidate points in (0, 1); per-case singular or non-real points are
# skipped after checking the integrand at x and x ± h. Arithmetic is Float64.
const FPOINTS = (0.21, 0.31, 0.43, 0.57, 0.71, 0.83)
const FNAMES = Symbol[:x; sort!(collect(keys(FPARAMS)); by = string)]

# Only expressions built from entire operations with nonnegative integer
# powers are asserted analytic at the complex sample. This is deliberately
# conservative: other expressions can be analytic, but are not asserted so.
function entire_integrand(source::AbstractString)
    tree = try Mapleish.julia_expr(source) catch; return false end
    function entire(ex)
        ex isa Number && return true
        ex isa Symbol && return true
        ex isa Expr && ex.head == :call || return false
        op, args = ex.args[1], ex.args[2:end]
        op in (:+, :-, :*, :sin, :cos, :sinh, :cosh, :exp) && return all(entire, args)
        op == :^ && length(args) == 2 && args[2] isa Integer && args[2] >= 0 && return entire(args[1])
        false
    end
    entire(tree)
end
const FCOMPLEX_POINT = 0.57 + 0.125im

# Screen local analyticity for a deliberately limited expression grammar at
# the requested sample, after substituting the case's fixed parameters.
# Unknown functions, poles and principal branch cuts fail closed. A finite
# nonzero denominator and a non-cut branch argument have an open analytic
# neighbourhood; Float64 screening at the finite-difference stencil adds a
# practical margin but is not a rigorous branch certificate.
function analytic_complex_sample(source::AbstractString, params::AbstractDict = FPARAMS;
                                 point::Complex = FCOMPLEX_POINT)
    tree = try Mapleish.julia_expr(source) catch; return false end
    depends_on_x(ex) = ex === :x || (ex isa Expr && any(depends_on_x, ex.args))
    nonzero(z) = isfinite(abs(z)) && abs(z) > 1e-10
    offcut(z) = nonzero(z) && (real(z) > 0 || abs(imag(z)) > 1e-8 * max(1, abs(z)))
    function evaluate(ex, z)
        ex isa Number && return ComplexF64(ex)
        if ex isa Symbol
            ex === :x && return ComplexF64(z)
            ex === :pi && return ComplexF64(pi)
            ex === :im && return ComplexF64(im)
            haskey(params, ex) || error("unbound symbol")
            return ComplexF64(params[ex])
        end
        ex isa Expr && ex.head === :call || error("unsupported syntax")
        op, args = ex.args[1], ex.args[2:end]
        v = [evaluate(a, z) for a in args]
        value = if op === :+
            sum(v; init=0.0+0.0im)
        elseif op === :- && length(v) == 1
            -v[1]
        elseif op === :- && length(v) == 2
            v[1] - v[2]
        elseif op === :*
            prod(v; init=1.0+0.0im)
        elseif op === :/ && length(v) == 2
            nonzero(v[2]) || error("possible pole")
            v[1] / v[2]
        elseif op === :^ && length(v) == 2
            integer_power = !depends_on_x(args[2]) && iszero(imag(v[2])) && isinteger(real(v[2]))
            if integer_power
                real(v[2]) >= 0 || nonzero(v[1]) || error("possible pole")
            else
                offcut(v[1]) || error("possible power branch cut")
            end
            integer_power ? v[1]^Int(real(v[2])) : v[1]^v[2]
        elseif op in (:sin, :cos, :sinh, :cosh, :exp) && length(v) == 1
            getfield(Base, op)(v[1])
        elseif op in (:tan, :tanh) && length(v) == 1
            denominator = op === :tan ? cos(v[1]) : cosh(v[1])
            nonzero(denominator) || error("possible pole")
            getfield(Base, op)(v[1])
        elseif op in (:log, :sqrt) && length(v) == 1
            offcut(v[1]) || error("possible principal branch cut")
            getfield(Base, op)(v[1])
        else
            error("unsupported analytic operation")
        end
        isfinite(abs(value)) || error("non-finite value")
        value
    end
    h = 1e-5
    try
        all(z -> (evaluate(tree, z); true), (point-h, point, point+h, point-im*h, point+im*h))
    catch
        false
    end
end

# The worker computes this flag before starting the measured operation.
# Direct adapter tests can derive it from the same inputs when unset.
function complex_sample_enabled(source, params)
    selected = BenchCommon.COMPLEX_SAMPLE_ENABLED[]
    selected === nothing ? analytic_complex_sample(source, params) : selected
end

unevaluated(out) = (s = string(out); occursin(r"integrate\(|Integral\(|∫|Integral\b|integral\(", s))

"""
    check_integral(out, integrand, reference; params = FPARAMS, certified = nothing)

Status and note for the answer `out` of a system to `∫ integrand dx`.
`reference` is the antiderivative the source gives (for the leaf-count grade;
"Unintegrable" means no closed form); `certified`, when given, is a Julia
expression text of a proved antiderivative (bench H), compared with the answer
up to a constant at the check points.
"""
function check_integral(out, integrand::String, reference::String; params::Dict{Symbol,Float64} = FPARAMS,
                        certified = nothing, real_points = FPOINTS, complex_point = nothing)
    s = string(out)
    leaves = leaf_count(s); ref = leaf_count(reference)
    grade_note(st) = isempty(reference) ? "leaves=$leaves" :
        (g = st == :verified ? (leaves <= 2ref ? "A" : "B") : st == :wrong ? "F" : "ungraded";
         "grade=$g leaves=$leaves ref=$ref")
    if occursin("Unintegrable", reference) || occursin("CannotIntegrate", reference)
        return unevaluated(s) ? (:unsolved, "reference has no closed form; returned unevaluated, as the reference; " * grade_note(:unsolved)) :
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
    samples = String[]
    Fvals = Tuple{Float64,ComplexF64}[]      # (x0, F(x0)) for the comparison with the certified antiderivative
    for x0 in real_points
        pt = Dict{Symbol,Float64}(params); pt[:x] = x0
        fx = try fev(pt) catch err; nothing end
        (fx === nothing || !isfinite(fx)) && continue
        abs(imag(fx)) > 1e-9 * max(abs(fx), 1.0) && continue      # only points where the integrand is real
        fx = real(fx)
        ptp = copy(pt); ptp[:x] = x0 + h
        ptm = copy(pt); ptm[:x] = x0 - h
        # Exclude obvious singularities or departures from the real branch
        # on either side of the finite-difference stencil.
        neighbors = (try fev(ptp) catch; nothing end, try fev(ptm) catch; nothing end)
        any(v -> v === nothing || !isfinite(v) || abs(imag(v)) > 1e-9 * max(abs(v), 1.0), neighbors) && continue
        Fp, Fm = EVAL(out, ptp), EVAL(out, ptm)
        (Fp === nothing || Fm === nothing) && continue
        dF = (Fp - Fm) / (2h)
        (isfinite(abs(dF)) && isfinite(abs(fx))) || continue
        npts += 1
        tol = 2e-4 * max(abs(fx), 1.0) + 1e-7     # a central difference of a long printed answer loses a few digits
        abs(dF - fx) <= tol || return (:wrong, "derivative mismatch at x=$x0: F'=$(dF) f=$(round(fx; sigdigits=6)); " * grade_note(:wrong))
        push!(samples, "$(x0):$(round(real(dF); sigdigits=5))/$(round(fx; sigdigits=5))")
        F0 = EVAL(out, pt)
        F0 === nothing || push!(Fvals, (x0, ComplexF64(F0)))
    end
    npts >= 4 || return (:unverified, "fewer than four real points could be evaluated; leaves=$leaves ref=$ref; samples=" * join(samples, ","))
    note = grade_note(:unverified) * "; Float64 x:Fprime/f=" * join(samples, ",")
    if cev !== nothing && length(Fvals) >= 2
        agree = true
        x1, F1 = Fvals[1]
        pt1 = Dict{Symbol,Float64}(params); pt1[:x] = x1
        R1 = try cev(pt1) catch err; nothing end
        if R1 === nothing || !isfinite(R1)
            note = "certified: not evaluable; " * note
        else
            for (xi, Fi) in Fvals[2:end]
                pti = Dict{Symbol,Float64}(params); pti[:x] = xi
                Ri = try cev(pti) catch err; nothing end
                (Ri === nothing || !isfinite(Ri)) && (agree = false; break)
                dF, dR = Fi - F1, Ri - R1
                abs(dF - dR) <= 1e-4 * max(abs(dR), 1.0) + 1e-6 || (agree = false; break)
            end
            note = (agree ? "certified: agree; " : "certified: differ; ") * note
        end
    end
    if complex_point !== nothing
        z = ComplexF64(complex_point)
        pt = Dict{Symbol,Number}(k => v for (k, v) in params); pt[:x] = z
        ptp = copy(pt); ptp[:x] = z + h
        ptm = copy(pt); ptm[:x] = z - h
        fz = try fev(pt) catch; nothing end
        fp = try EVAL(out, ptp) catch; nothing end
        fm = try EVAL(out, ptm) catch; nothing end
        pti_p = copy(pt); pti_p[:x] = z + im*h
        pti_m = copy(pt); pti_m[:x] = z - im*h
        fi_p = try EVAL(out, pti_p) catch; nothing end
        fi_m = try EVAL(out, pti_m) catch; nothing end
        (fz === nothing || fp === nothing || fm === nothing || fi_p === nothing || fi_m === nothing) &&
            return (:unverified, note * "; complex point $z not evaluable")
        dz = (fp - fm) / (2h)
        dzi = (fi_p - fi_m) / (2im*h)
        (isfinite(abs(fz)) && isfinite(abs(dz)) && isfinite(abs(dzi))) || return (:unverified, note * "; complex point $z non-finite")
        tol = 2e-4 * max(abs(fz), 1.0) + 1e-7
        cr_tol = 2e-4 * max(abs(dz), abs(dzi), 1.0) + 1e-7
        abs(dz - dzi) <= cr_tol || return (:unverified, note * "; non-holomorphic or branch-discontinuous answer at $z: real-direction=$dz imaginary-direction=$dzi")
        abs(dz - fz) <= tol || return (:wrong, replace(note, grade_note(:unverified) => grade_note(:wrong); count=1) *
                                      "; complex mismatch at $z: F'=$dz f=$fz")
        short(v) = string(round(real(v); sigdigits=5), imag(v) < 0 ? "" : "+", round(imag(v); sigdigits=5), "im")
        note *= "; complex x=$z Fprime=$(short(dz)) f=$(short(fz))"
    end
    note = replace(note, grade_note(:unverified) => grade_note(:verified); count=1)
    (:verified_numeric, note)
end
