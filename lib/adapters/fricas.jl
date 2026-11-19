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
Base.string(a::FricasAnswer) = a.text

check_points() = (pts = Main.FPOINTS; h = 1e-5; [x0 + s * h for x0 in pts for s in (-1, 1)])
param_list(xv) = join(["$k = $(v)" for (k, v) in Main.FPARAMS] ∪ ["x = $xv"], ", ")

function run_fricas(script::String)
    out = IOBuffer()
    run(pipeline(`$FRICAS -nosman -eval ")read $(script) )quiet"`; stdout = out, stderr = devnull))
    String(take!(out))
end

function INTEGRATE_TEXT(integrand::String, var::String)
    f = Mapleish.translate(integrand, :fricas)
    xs = check_points()
    lines = [")set message autoload off", ")set message type off", ")set output algebra off",
             "f := $f", "F := integrate(f, $var)",
             "output(concat(\"<<ANS>>\", unparse(F::InputForm)))"]
    for (i, xv) in enumerate(xs)
        push!(lines, "v$i := complexNumeric(eval(F, [$(param_list(xv))]))")
        push!(lines, "output(concat(\"<<V$i>>\", unparse(v$i::InputForm)))")
    end
    path = tempname() * ".input"
    write(path, join(lines, "\n") * "\n")
    txt = try
        run_fricas(path)
    finally
        rm(path; force = true)
    end
    m = match(r"<<ANS>>\s*(.*)", txt)
    m === nothing && error("fricas gave no answer: " * first(replace(txt, "\n" => " "), 200))
    ans = strip(m[1])
    vals = Dict{Float64,ComplexF64}()
    for (i, xv) in enumerate(xs)
        mv = match(Regex("<<V$i>>\\s*(.*)"), txt)
        mv === nothing && continue
        v = parse_fricas_number(strip(mv[1]))
        v === nothing || (vals[xv] = v)
    end
    FricasAnswer(ans, vals)
end

# "complex(1.2,3.4)", "1.2", "-5.6E-3", "complex(1.2,- 3.4)"
function parse_fricas_number(s::AbstractString)
    s = replace(s, " " => "", "E" => "e")
    m = match(r"^complex\(([^,]+),([^)]+)\)$", s)
    m !== nothing && return (try ComplexF64(parse(Float64, m[1]), parse(Float64, m[2])) catch; nothing end)
    try
        ComplexF64(parse(Float64, s))
    catch
        nothing
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
