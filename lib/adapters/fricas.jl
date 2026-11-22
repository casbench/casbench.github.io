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
const CASE_LIMIT = get(ENV, "BENCH_CASE_TIMEOUT", "600")   # seconds; a subprocess never outlives the case

struct FricasAnswer
    text::String
    values::Dict{ComplexF64,ComplexF64}
    answer_ns::UInt64
end
const REPEATS = 1                      # one process per case
Base.string(a::FricasAnswer) = a.text

function check_points(integrand, params)
    h = 1e-5
    xs = ComplexF64[x0 + s*h for x0 in Main.FPOINTS for s in (-1, 0, 1)]
    if Main.complex_sample_enabled(integrand, params)
        append!(xs, (Main.FCOMPLEX_POINT - h, Main.FCOMPLEX_POINT + h, Main.FCOMPLEX_POINT - im*h, Main.FCOMPLEX_POINT + im*h))
    end
    xs
end
fricas_point(z, cplx) = iszero(imag(z)) ? "($(real(z))$(cplx ? "::Complex Float" : "::Float"))" :
    "complex($(real(z))::Float,$(imag(z))::Float)"
# only the parameters the integrand uses (D is FriCAS's differentiation operator, F and others are fine as symbols)
# values substituted as Complex Float, so that a logarithm or a root of a negative value evaluates instead of raising
param_list(xv, integrand, params, cplx) = (ty = cplx ? "::Complex Float" : "::Float";
    join([["$k = ($(v)$ty)" for (k, v) in params if occursin(Regex("\\b$k\\b"), integrand)]; "x = $(fricas_point(xv, cplx))"], ", "))

function run_fricas(script::String)
    cmd = pipeline(`timeout -k 5 $CASE_LIMIT $FRICAS -nosman -eval ")read $(script) )quiet" -eval ")quit"`; stderr=devnull)
    io = open(cmd, "r")
    lines = String[]
    answer_ns = UInt64(0)
    try
        for line in eachline(io)
            push!(lines, line)
            if answer_ns == 0 && occursin("<<DONE>>", line)
                answer_ns = time_ns()
                answer = marker_text(join(lines, "\n"), "<<ANS>>")
                answer === nothing || notify_answer(answer, answer_ns)
            end
        end
    finally
        close(io)
    end
    txt = join(lines, "\n")
    get(ENV, "BENCH_DEBUG", "0") == "1" && (println(stderr, "--- fricas script\n", read(script, String), "--- fricas output\n", txt); flush(stderr))
    txt, answer_ns
end

function INTEGRATE_TEXT(integrand::String, var::String, params = Main.FPARAMS)
    f = Mapleish.translate(integrand, :fricas)
    xs = check_points(integrand, params)
    lines = [")set message autoload off", ")set message type off", ")set output algebra off", ")set output length 245", ")set break resume",
             "f := $f", "resf := integrate(f, $var)",
             "output(concat(\"<<ANS>>\", unparse(resf::InputForm)))",
             "output(concat(\"<<DO\", \"NE>>\"))", ")lisp (finish-output)"]
    for (i, xv) in enumerate(xs)
        # real values first (an Expression Integer evaluates cleanly), complex ones second (logarithms of negative values);
        # with )set break resume an error in one line does not stop the next
        push!(lines, "v$i := complexNumeric(eval(resf, [$(param_list(xv, integrand, params, false))]))")
        push!(lines, "output(concat(\"<<V$i>>\", unparse(v$i::InputForm)))")
        push!(lines, "w$i := complexNumeric(eval(resf, [$(param_list(xv, integrand, params, true))]))")
        push!(lines, "output(concat(\"<<W$i>>\", unparse(w$i::InputForm)))")
    end
    path = tempname() * ".input"
    write(path, join(lines, "\n") * "\n")
    log_input!(join(lines, "\n"))
    txt, answer_ns = try
        run_fricas(path)
    finally
        rm(path; force = true)
    end
    ans = marker_text(txt, "<<ANS>>")
    ans === nothing && error("fricas gave no answer: " * last(strip(replace(txt, "\n" => " ")), 200))
    vals = Dict{ComplexF64,ComplexF64}()
    for (i, xv) in enumerate(xs)
        for mk in ("<<V$i>>", "<<W$i>>")
            mv = marker_text(txt, mk)
            mv === nothing && continue
            v = parse_fricas_number(mv)
            v === nothing && continue
            vals[xv] = v
            break
        end
    end
    FricasAnswer(ans, vals, answer_ns)
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
EVAL(ex, vals) = ex isa FricasAnswer ? get(ex.values, ComplexF64(vals[:x]), nothing) : (ex isa Number ? ex : nothing)
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

function VERIFY_INTEGRAL_COMMAND(answer::String, integrand::String, var::String)
    f = Mapleish.translate(integrand, :fricas)
    join([")set message autoload off", ")set message type off", ")set output algebra off",
          ")set output length 245", ")set break resume", "f := " * f, "F := " * answer,
          "r := simplify(D(F," * var * ")-f)", "output(concat(\"<<RES>>\",unparse(r::InputForm)))"], "\n") * "\n"
end
function VERIFY_INTEGRAL(answer::String, integrand::String, var::String)
    path = tempname() * ".input"
    write(path, VERIFY_INTEGRAL_COMMAND(answer, integrand, var))
    try
        txt, _ = run_fricas(path)
        value = marker_text(txt, "<<RES>>")
        value === nothing ? "" : strip(value)
    finally
        rm(path; force=true)
    end
end
OPS[:VERIFY_INTEGRAL] = VERIFY_INTEGRAL
