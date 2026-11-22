# SageMath adapter (benches F and G), as a subprocess: one Sage process per
# worker (sage_server.py), fed one script per case. The thin files sage_<algorithm>.jl set SAGE_ALGORITHM and include
# this one, so that Sage drives one engine per system column:
#   F: integrate(f, x, algorithm=...)  with maxima, fricas, sympy
#      (the configuration of the 12000.org tests for Maxima and FriCAS); for giac,
#      Sage's pexpect interface to the giac binary (nixpkgs' Sage lacks the
#      sagemath_giac library binding, and algorithm='giac' then returns the
#      integral unevaluated), the answer converted back with .sage()
#   G: ideal.groebner_basis('libsingular:std') (singular), or gbasis through the
#      same giac interface
# The script prints the answer, Sage's own wall time of the call (the warm
# time; the first-call time includes Sage's start-up) and, for F, the complex
# numeric value of the answer at the six check points.
#
# Needs `sage` on PATH (the Nix toolchain provides it); algorithm fricas
# needs `fricas` on PATH as well.
isdefined(Main, :SAGE_ALGORITHM) || error("include sage.jl through a sage_<algorithm>.jl file")
const SYSTEM = "Sage/" * Dict("giac" => "Giac", "maxima" => "Maxima", "fricas" => "FriCAS", "sympy" => "SymPy", "singular" => "Singular")[SAGE_ALGORITHM]
const VAR = Dict{Symbol,Any}()
const REPEATS = 1

isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "mapleish.jl"))
isdefined(Main, :Poly) || include(joinpath(@__DIR__, "..", "poly.jl"))

const SAGE = get(ENV, "SAGE", "sage")
const CASE_LIMIT = get(ENV, "BENCH_CASE_TIMEOUT", "600")   # seconds; a subprocess never outlives the case

struct SageAnswer
    text::String
    values::Dict{ComplexF64,ComplexF64}
    elapsed::Float64
    answer_ns::UInt64
end
Base.string(a::SageAnswer) = a.text

struct SageBasis
    polys::Vector{String}
    elapsed::Float64
end
Base.string(b::SageBasis) = string(b.polys)
Base.length(b::SageBasis) = length(b.polys)
Base.iterate(b::SageBasis, st...) = iterate(b.polys, st...)
Base.isempty(b::SageBasis) = isempty(b.polys)

function check_points(integrand)
    h = 1e-5
    xs = ComplexF64[x0 + s*h for x0 in Main.FPOINTS for s in (-1, 0, 1)]
    if Main.entire_integrand(integrand)
        append!(xs, (Main.FCOMPLEX_POINT - h, Main.FCOMPLEX_POINT + h))
    end
    xs
end
sage_point(z) = iszero(imag(z)) ? string(real(z)) : "CC(" * string(real(z)) * "," * string(imag(z)) * ")"

# one Sage process per worker (lib/adapters/sage_server.py), fed the path of a script per case; restarted if it died
const SAGE_PROC = Ref{Any}(nothing)
function sage_process()
    p = SAGE_PROC[]
    if p === nothing || !process_running(p)
        p = open(`$SAGE -python $(joinpath(@__DIR__, "sage_server.py"))`, "r+")
        t0 = time()
        while time() - t0 < 120
            l = readline(p)
            (l == "<<READY>>" || (!process_running(p) && eof(p))) && break
        end
        SAGE_PROC[] = p
    end
    p
end

function run_sage(script::String; capture_answer=false)
    log_input!(script)
    path = tempname() * ".sage"
    write(path, script)
    out = IOBuffer()
    answer_ns = UInt64(0)
    try
        p = sage_process()
        println(p, path); flush(p)
        while true
            (eof(p) && !process_running(p)) && break
            l = readline(p)
            l == "<<END>>" && break
            if answer_ns == 0 && startswith(l, "<<ANS>>")
                answer_ns = time_ns()
                answer = marker(l, "<<ANS>>")
                answer === nothing || notify_answer(answer, answer_ns)
            end
            println(out, l)
        end
    finally
        rm(path; force = true)
    end
    txt = String(take!(out))
    get(ENV, "BENCH_DEBUG", "0") == "1" && (println(stderr, "--- sage script\n", script, "--- sage output\n", txt); flush(stderr))
    capture_answer ? (txt, answer_ns) : txt
end

marker(txt, m) = (r = match(Regex(m * raw"\s*(.*)"), txt); r === nothing ? nothing : strip(r[1]))

# "1.23 + 0.45*I", "1.23", "-0.5*I", "1.23 - 0.45*I"
function parse_sage_complex(s::AbstractString)
    s = replace(s, " " => "")
    m = match(r"^([+-]?[0-9.]+(?:e[+-]?\d+)?)?([+-][0-9.]*(?:e[+-]?\d+)?)?\*?I?$", s)
    m === nothing && return nothing
    try
        re = m[1] === nothing ? 0.0 : parse(Float64, m[1])
        im = 0.0
        if occursin("I", s)
            if m[2] === nothing            # the real part was the imaginary one, "0.45*I"
                im, re = re, 0.0
            else
                t = m[2]; t in ("+", "-") && (t *= "1"); im = parse(Float64, t)
            end
        end
        ComplexF64(re, im)
    catch
        nothing
    end
end

function INTEGRATE_TEXT(integrand::String, var::String, params = Main.FPARAMS)
    f = Mapleish.translate(integrand, :sage)
    # the symbols of the integrand: identifiers that are not function names ("c" is a symbol even when "csc(" occurs)
    syms = unique([m.match for m in eachmatch(r"\b[A-Za-z_][A-Za-z_0-9]*\b", f)
                   if !occursin(Regex("\\b" * m.match * "\\("), f) && !(m.match in ("pi", "I", "e", "E"))])
    used = [k for (k, v) in params if string(k) in syms]
    pt = join(["$k: $(v)" for (k, v) in params if k in used], ", ")
    # the sign of each parameter is assumed as its fixed value has it (Maxima asks otherwise)
    assumptions = ["assume($k " * (params[k] > 0 ? ">" : "<") * " 0)" for k in used if params[k] != 0]
    lines = ["var('" * join(unique([var; string.(used)]), " ") * "')", assumptions...,
             "t0 = walltime()",
             "try:",
             "    f = $f",
             SAGE_ALGORITHM == "giac" ? "    Fg = giac(f).integrate(giac($var))\n    t1 = walltime()\n    try:\n        F = Fg.sage()\n    except Exception as ex:\n        F = str(Fg)   # an unevaluated integral or a form Sage cannot read back: kept as text" :
                                        "    F = integrate(f, $var, algorithm='$SAGE_ALGORITHM')\n    t1 = walltime()",
             "except Exception as ex:",
             "    print('<<' + 'ANS>>', 'sage_error: ' + str(ex)[:200])",
             "    print('<<' + 'TIME>>', walltime() - t0)",
             "    raise SystemExit(0)",
             "print('<<' + 'ANS>>', str(F))", "print('<<' + 'TIME>>', t1 - t0)"]
    xs = check_points(integrand)
    for (i, xv) in enumerate(xs)
        point = sage_point(xv)
        push!(lines, "try:\n    v = CC(F.subs({$var: $point" * (isempty(pt) ? "" : ", " * pt) * "}))\n    print('<<' + 'V$i>>', str(v))\nexcept Exception as ex:\n    print('<<' + 'V$i>>', 'fail')")
    end
    txt, answer_ns = run_sage(join(lines, "\n") * "\n"; capture_answer=true)
    ans = marker(txt, "<<ANS>>")
    ans === nothing && error("sage gave no answer: " * last(strip(replace(txt, "\n" => " ")), 300))
    # an exception inside Sage is an error of the interface (e.g. the pexpect giac interface cannot parse an answer that
    # giac prints with a warning), unless the system declares that it cannot integrate (then the worker says unsolved)
    startswith(ans, "sage_error:") && !occursin(r"not implemented|NotImplemented|cannot|unable", ans) && error(ans)
    vals = Dict{ComplexF64,ComplexF64}()
    for (i, xv) in enumerate(xs)
        v = marker(txt, "<<V$i>>")
        (v === nothing || v == "fail") && continue
        c = parse_sage_complex(v)
        c === nothing || (vals[xv] = c)
    end
    t = marker(txt, "<<TIME>>")
    SageAnswer(ans, vals, t === nothing ? NaN : parse(Float64, t), answer_ns)
end

function GROEBNER(polys::Vector{String}, vars::Vector{String}, p::Int)
    SAGE_ALGORITHM in ("singular", "giac") || error("no Gröbner basis through Sage with $SAGE_ALGORITHM")
    ring = p == 0 ? "QQ" : "GF($p)"
    L = "[" * join([replace(s, "//" => "/") for s in polys], ", ") * "]"
    V = "[" * join(vars, ",") * "]"
    lines = SAGE_ALGORITHM == "singular" ?
        ["R = PolynomialRing($ring, '" * join(vars, ",") * "', order='degrevlex')",
         "R.inject_variables(verbose=False)", "I = R.ideal($L)",
         "t0 = walltime()", "B = I.groebner_basis('libsingular:std')", "t1 = walltime()",
         "print('<<' + 'TIME>>', t1 - t0)", "for g in B:", "    print('<<' + 'G>>', str(g))"] :
        ["t0 = walltime()", "B = giac('gbasis(" * (p == 0 ? L : L * " % $p") * ",$V,revlex)')", "t1 = walltime()",
         "print('<<' + 'TIME>>', t1 - t0)", "for g in B:", "    print('<<' + 'G>>', str(g).replace(' % $p', ''))"]
    txt = run_sage(join(lines, "\n") * "\n")
    gs = [strip(m[1]) for m in eachmatch(r"<<G>>\s*(.*)", txt)]
    isempty(gs) && error("sage gave no basis: " * last(strip(replace(txt, "\n" => " ")), 200))
    t = marker(txt, "<<TIME>>")
    SageBasis(gs, t === nothing ? NaN : parse(Float64, t))
end

function RUR(polys::Vector{String}, vars::Vector{String})
    SAGE_ALGORITHM == "singular" || error("unsupported operation: no RUR for this Sage engine")
    script = "INPUT_POLYS = " * repr(polys) * "\nINPUT_VARS = " * repr(vars) * "\n" *
             read(joinpath(@__DIR__, "sage_rur.py"), String)
    txt = run_sage(script)
    msg = marker(txt, "<<ANS>>")
    msg === nothing || error(msg)
    parseq(s) = begin
        parts = split(strip(s), '/'; limit=2)
        parse(BigInt, parts[1]) // (length(parts) == 2 ? parse(BigInt, parts[2]) : big(1))
    end
    list(s) = isempty(strip(s)) ? Rational{BigInt}[0] : parseq.(split(s, ','))
    elim, denom, elapsed = marker(txt, "<<ELIM>>"), marker(txt, "<<DEN>>"), marker(txt, "<<TIME>>")
    (elim === nothing || denom === nothing || elapsed === nothing) && error("sage gave no RUR")
    params = [list(m[1]) for m in eachmatch(r"<<PAR>>[ \t]*([^\r\n]*)", txt)]
    solutions = [list(m[1]) for m in eachmatch(r"<<SOL>>[ \t]*([^\r\n]*)", txt)]
    (vars=vars, linear_form=String[], parameter_index=length(vars), elim=list(elim), denom=list(denom),
     param=params, solutions=solutions, elapsed=parse(Float64, elapsed))
end

const OPS = Dict{Symbol,Any}(:integrate_text => INTEGRATE_TEXT, :groebner => GROEBNER)
SAGE_ALGORITHM == "singular" && (OPS[:rur] = RUR)
EVAL(ex, vals) = ex isa SageAnswer ? get(ex.values, ComplexF64(vals[:x]), nothing) : (ex isa Number ? ex : nothing)
NTERMS(ex) = 1
NFACTORS(ex) = 1
UNSOLVED(op, out) = out isa SageAnswer && occursin(r"integrate\(|sage_error: .*(not implemented|NotImplemented|cannot|unable)", out.text)
CLEARCACHE() = nothing
function VERSIONS()
    v = try
        strip(read(pipeline(`$SAGE --version`; stderr = devnull), String))
    catch
        "unknown"
    end
    ["SageMath" => first(v, 60), "sage_algorithm" => SAGE_ALGORITHM]
end

# Sage's adapters ask the underlying engine to simplify its own derivative
# residual. Parsing or unsupported engine interfaces yield verify_unsolved.
function VERIFY_INTEGRAL_COMMAND(answer::String, integrand::String, variable::String)
    f = Mapleish.translate(integrand, :sage)
    words = unique([m.match for m in eachmatch(r"\b[A-Za-z_][A-Za-z_0-9]*\b", f)
                    if !occursin(Regex("\\b" * m.match * "\\("), f) && !(m.match in ("pi", "I", "e", "E"))])
    symbols = join(unique([variable; words]), " ")
    lines = ["var(" * repr(symbols) * ")", "f = SR(" * f * ")", "F = SR(" * answer * ")"]
    if SAGE_ALGORITHM == "giac"
        push!(lines, "r = giac('simplify(diff((' + str(giac(F)) + '),' + str(giac(" * variable * ")) + ')-(' + str(giac(f)) + '))')")
    elseif SAGE_ALGORITHM == "maxima"
        push!(lines, "r = (F._maxima_().diff(" * variable * "._maxima_()) - f._maxima_()).radcan().ratsimp()")
    elseif SAGE_ALGORITHM == "fricas"
        push!(lines, "r = (fricas(F).D(fricas(" * variable * ")) - fricas(f)).simplify()")
    elseif SAGE_ALGORITHM == "sympy"
        push!(lines, "import sympy as sp")
        push!(lines, "r = sp.simplify(sp.diff(F._sympy_(), sp.Symbol(" * repr(variable) * ")) - f._sympy_())")
    else
        error("no integration self-check for this Sage engine")
    end
    push!(lines, "print('<<' + 'RES>>', str(r))")
    join(lines, "\n") * "\n"
end
function VERIFY_INTEGRAL(answer::String, integrand::String, variable::String)
    txt = run_sage(VERIFY_INTEGRAL_COMMAND(answer, integrand, variable))
    value = marker(txt, "<<RES>>")
    value === nothing ? "" : value
end
OPS[:VERIFY_INTEGRAL] = VERIFY_INTEGRAL
