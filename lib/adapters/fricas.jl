# FriCAS adapter (bench F), as a subprocess: one `fricas -nosman` per case,
# fed a script that integrates the translated integrand, prints the answer in
# input syntax (`unparse`) and the complex numeric value of the answer at the
# six points the check needs. EVAL looks those values up (see maxima.jl).
#
# Needs `fricas` on PATH (the Nix toolchain provides it).
const SYSTEM = "FriCAS"
const VAR = Dict{Symbol,Any}()

isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "mapleish.jl"))

const FRICAS = get(ENV, "FRICAS", "fricas")

struct FricasAnswer
    text::String
    values::Dict{Float64,ComplexF64}
end
const REPEATS = 1                      # one process per case
Base.string(a::FricasAnswer) = a.text

check_points() = (pts = Main.FPOINTS; h = 1e-5; [x0 + s * h for x0 in pts for s in (-1, 1)])
# only the parameters the integrand uses (D is FriCAS's differentiation operator, F and others are fine as symbols)
# values substituted as Complex Float, so that a logarithm or a root of a negative value evaluates instead of raising
param_list(xv, integrand) = join([["$k = ($(v)::Complex Float)" for (k, v) in Main.FPARAMS if occursin(Regex("\\b$k\\b"), integrand)]; "x = ($xv::Complex Float)"], ", ")

function run_fricas(script::String)
    out = IOBuffer()
    run(pipeline(`$FRICAS -nosman -eval ")read $(script) )quiet" -eval ")quit"`; stdout = out, stderr = devnull))
    String(take!(out))
end

function INTEGRATE_TEXT(integrand::String, var::String)
    f = Mapleish.translate(integrand, :fricas)
    xs = check_points()
    lines = [")set message autoload off", ")set message type off", ")set output algebra off", ")set output length 245",
             "f := $f", "resf := integrate(f, $var)",
             "output(concat(\"<<ANS>>\", unparse(resf::InputForm)))"]
    for (i, xv) in enumerate(xs)
        push!(lines, "v$i := complexNumeric(eval(resf, [$(param_list(xv, integrand))]))")
        push!(lines, "output(concat(\"<<V$i>>\", unparse(v$i::InputForm)))")
    end
    path = tempname() * ".input"
    write(path, join(lines, "\n") * "\n")
    txt = try
        run_fricas(path)
    finally
        rm(path; force = true)
    end
    ans = marker_text(txt, "<<ANS>>")
    ans === nothing && error("fricas gave no answer: " * last(strip(replace(txt, "\n" => " ")), 200))
    vals = Dict{Float64,ComplexF64}()
    for (i, xv) in enumerate(xs)
        mv = marker_text(txt, "<<V$i>>")
        mv === nothing && continue
        v = parse_fricas_number(mv)
        v === nothing || (vals[xv] = v)
    end
    FricasAnswer(ans, vals)
end

# the text after a marker, with the continuation lines FriCAS indents joined to it
function marker_text(txt::AbstractString, marker::AbstractString)
    lines = split(txt, '\n')
    j = findfirst(l -> occursin(marker, l), lines)
    j === nothing && return nothing
    out = IOBuffer()
    print(out, strip(lines[j][findfirst(marker, lines[j])[end]+1:end]))
    k = j + 1
    while k <= length(lines) && !isempty(strip(lines[k])) && !occursin("<<", lines[k])
        print(out, strip(lines[k])); k += 1
    end
    String(take!(out))
end

# unparse writes a Float as float(mantissa,exponent,base): m * base^exponent
function fricas_float(s::AbstractString)
    m = match(r"^float\((-?\d+),(-?\d+),(\d+)\)$", s)
    m !== nothing && return Float64(parse(BigInt, m[1]) * (big(1.0) * parse(Int, m[3]))^parse(Int, m[2]))
    parse(Float64, s)
end

# "complex(float(18001,-69,2),float(0,0,2))", "float(3,-1,2)", "1.2", "-5.6E-3"
function parse_fricas_number(s::AbstractString)
    s = replace(s, " " => "", "E" => "e")
    m = match(r"^complex\((float\([^)]*\)|[^,]+),(float\([^)]*\)|[^)]+)\)$", s)
    m !== nothing && return (try ComplexF64(fricas_float(m[1]), fricas_float(m[2])) catch; nothing end)
    try
        ComplexF64(fricas_float(s))
    catch
        return nothing
    end
end

const OPS = Dict{Symbol,Any}(:integrate_text => INTEGRATE_TEXT)
EVAL(ex, vals) = ex isa FricasAnswer ? get(ex.values, vals[:x], nothing) : (ex isa Number ? ex : nothing)
NTERMS(ex) = 1
NFACTORS(ex) = 1
UNSOLVED(op, out) = out isa FricasAnswer && occursin(r"integral\(|integrate\(", out.text)
CLEARCACHE() = nothing
function VERSIONS()
    v = try
        strip(read(pipeline(`$FRICAS -nosman -eval ")version"`; stderr = devnull), String))
    catch
        "unknown"
    end
    ["FriCAS" => first(replace(v, "\n" => " "), 80)]
end
