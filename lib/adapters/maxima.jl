# Maxima adapter (bench F), as a subprocess: one `maxima --very-quiet --batch`
# per case, which integrates the translated integrand, prints the answer in
# one line and the numeric value of the answer at the six points the check
# needs (x0 ± h for the three x0, every parameter at its fixed value). EVAL
# then only looks those values up, so the check stays the generic one.
#
# Needs `maxima` on PATH (the Nix toolchain provides it).
const SYSTEM = "Maxima"
const VAR = Dict{Symbol,Any}()

isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "mapleish.jl"))

const MAXIMA = get(ENV, "MAXIMA", "maxima")

struct MaximaAnswer
    text::String                       # the antiderivative as Maxima prints it (1D)
    values::Dict{Float64,ComplexF64}   # x => numeric value of the answer at the check points
end
Base.string(a::MaximaAnswer) = a.text

# points of the check (FPOINTS, FPARAMS and h of F_integration/problems.jl, read at call time)
check_points() = (pts = Main.FPOINTS; h = 1e-5; [x0 + s * h for x0 in pts for s in (-1, 1)])
param_list() = join(["$k=$(v)" for (k, v) in Main.FPARAMS], ",")

function run_maxima(script::String)
    out = IOBuffer()
    cmd = pipeline(`$MAXIMA --very-quiet --batch-string=$script`; stdout = out, stderr = devnull)
    run(cmd)
    String(take!(out))
end

function INTEGRATE_TEXT(integrand::String, var::String)
    f = Mapleish.translate(integrand, :maxima)
    xs = check_points()
    lines = ["display2d:false\$", "ratprint:false\$", "F: integrate($f, $var)\$",
             "print(\"<<ANS>>\", string(F))\$"]
    for (i, xv) in enumerate(xs)
        push!(lines, "print(\"<<V$i>>\", string(float(rectform(ev(F, $var=$xv, $(param_list()), numer)))))\$")
    end
    txt = run_maxima(join(lines, "\n"))
    m = match(r"<<ANS>>\s*(.*)", txt)
    m === nothing && error("maxima gave no answer: " * first(txt, 200))
    ans = strip(m[1])
    vals = Dict{Float64,ComplexF64}()
    for (i, xv) in enumerate(xs)
        mv = match(Regex("<<V$i>>\\s*(.*)"), txt)
        mv === nothing && continue
        v = parse_maxima_number(strip(mv[1]))
        v === nothing || (vals[xv] = v)
    end
    MaximaAnswer(ans, vals)
end

# "1.234", "-5.6e-3", "1.2*%i+3.4", "3.4-1.2*%i", "%i*1.2"
function parse_maxima_number(s::AbstractString)
    s = replace(s, " " => "")
    occursin(r"^[+-]?\d+(\.\d*)?([eE][+-]?\d+)?$", s) && return ComplexF64(parse(Float64, s))
    m = match(r"^([+-]?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)?([+-]\d*(?:\.\d*)?(?:[eE][+-]?\d+)?)\*%i$", s)
    if m !== nothing
        re = m[1] === nothing ? 0.0 : parse(Float64, m[1])
        ims = m[2]; ims in ("+", "-") && (ims *= "1")
        return ComplexF64(re, parse(Float64, ims))
    end
    m = match(r"^([+-]?\d*(?:\.\d*)?(?:[eE][+-]?\d+)?)\*%i([+-]\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)$", s)
    if m !== nothing
        return ComplexF64(parse(Float64, m[2]), parse(Float64, m[1] in ("", "+", "-") ? m[1] * "1" : m[1]))
    end
    nothing
end

const OPS = Dict{Symbol,Any}(:integrate_text => INTEGRATE_TEXT)
EVAL(ex, vals) = ex isa MaximaAnswer ? get(ex.values, vals[:x], nothing) : (ex isa Number ? ex : nothing)
NTERMS(ex) = 1
NFACTORS(ex) = 1
UNSOLVED(op, out) = out isa MaximaAnswer && occursin(r"integrate\(|'integrate", out.text)
CLEARCACHE() = nothing
function VERSIONS()
    v = try
        strip(read(`$MAXIMA --version`, String))
    catch
        "unknown"
    end
    ["Maxima" => replace(v, r"^Maxima\s*" => "")]
end
