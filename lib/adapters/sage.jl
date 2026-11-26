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
    alternatives::Vector{SageAnswer}     # the forms of a list answer, each with its values (lib/integration_check.jl)
end
SageAnswer(text, values, elapsed, answer_ns) = SageAnswer(text, values, elapsed, answer_ns, SageAnswer[])
Base.string(a::SageAnswer) = a.text

struct SageBasis
    polys::Vector{String}
    elapsed::Float64
end
Base.string(b::SageBasis) = string(b.polys)
Base.length(b::SageBasis) = length(b.polys)
Base.iterate(b::SageBasis, st...) = iterate(b.polys, st...)
Base.isempty(b::SageBasis) = isempty(b.polys)

function check_points(integrand, params)
    h = 1e-5
    xs = ComplexF64[x0 + s*h for x0 in Main.FPOINTS for s in (-1, 0, 1)]
    if Main.complex_sample_enabled(integrand, params)
        append!(xs, (Main.FCOMPLEX_POINT - h, Main.FCOMPLEX_POINT + h, Main.FCOMPLEX_POINT - im*h, Main.FCOMPLEX_POINT + im*h))
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
                   if !occursin(Regex("\\b" * m.match * "\\("), f) && !(m.match in ("pi", "I", "E"))])
    used = [k for (k, v) in params if string(k) in syms]
    pt = join(["$k: $(v)" for (k, v) in params if k in used], ", ")
    # the sign of each parameter is assumed as its fixed value has it (Maxima asks otherwise)
    assumptions = ["assume($k " * (params[k] > 0 ? ">" : "<") * " 0)" for k in used if params[k] != 0]
    # Giac through Sage: Sage's giac interface raises on any output containing "error" and reads Giac's warnings
    # ("Simplification assuming c near 0", "Warning, integration of abs or sign assumes ...") as the answer; the
    # integral is computed with the base Expect._eval_line into a Giac variable, read back afterwards, and only a
    # line with Giac's own error mark "Error:" raises (before 2026-11-26: errors and false answers). Giac runs on one
    # thread, as in every Giac column (docs/benches.md), set before the timed call. The variable is passed by its
    # Giac name (sageVARx), as Sage's own call does: int(f, sage1) would take sage1 for a new variable.
    # The result variable is reset before each call: a failed int leaves it unassigned (Giac does not always print
    # "Error:", for instance "Degree mismatch inside factorisation"), and the previous case's value must not be read.
    # Giac reprints its warnings each time some results are evaluated, so that Sage cannot convert them: that is an
    # error of the interface, not an answer (before 2026-11-26 the warning text itself was recorded as the answer).
    integrate_giac = "    _casbench_gf = giac(_casbench_integrand)\n" *
        "    _casbench_out = Expect._eval_line(giac, 'casbench_F:=int(' + _casbench_gf.name() + ',' + str(giac($var)) + '):;', allow_use_file=False)\n" *
        "    t1 = walltime()\n" *
        "    _casbench_failed = [l for l in _casbench_out.splitlines() if 'Error:' in l]\n" *
        "    if _casbench_failed: raise RuntimeError('giac: ' + ' | '.join(_casbench_failed))\n" *
        "    if Expect._eval_line(giac, 'type(casbench_F)', allow_use_file=False).strip().splitlines()[-1] == 'string':\n" *
        "        raise RuntimeError('giac gave no antiderivative: ' + ' '.join(_casbench_out.split())[:600])\n" *
        "    _casbench_giac_answer = giac('casbench_F')\n" *
        "    try:\n        _casbench_answer = _casbench_giac_answer.sage()\n" *
        "    except Exception as ex:\n" *
        "        _casbench_text = str(_casbench_giac_answer)\n" *
        "        _casbench_msgs = [l for l in _casbench_text.splitlines() if l.startswith(('Simplification assuming', 'Warning', 'Check ['))]\n" *
        "        if _casbench_msgs: raise RuntimeError('Sage cannot read the answer: Giac prints messages each time it is evaluated (' + _casbench_msgs[0] + ')')\n" *
        "        _casbench_answer = _casbench_text"
    lines = ["var('" * join(unique([var; string.(used)]), " ") * "')", assumptions...,
             (SAGE_ALGORITHM == "giac" ? ["from sage.interfaces.expect import Expect", "giac.eval('threads:=1')",
                                          "Expect._eval_line(giac, 'casbench_F:=\"casbench_unset\":;', allow_use_file=False)"] : String[])...,
             "t0 = walltime()",
             "try:",
             "    _casbench_integrand = $f",
             SAGE_ALGORITHM == "giac" ? integrate_giac :
                                        "    _casbench_answer = integrate(_casbench_integrand, $var, algorithm='$SAGE_ALGORITHM')\n    t1 = walltime()",
             "except Exception as ex:",
             # the exception's type and its whole text on one line (before 2026-11-26: the first 200 characters, often
             # empty or cut before the reason); the full repr also goes to the worker's log
             "    import sys",
             "    print('casbench sage_error:', repr(ex), file=sys.stderr)",
             "    print('<<' + 'ANS>>', 'sage_error: ' + type(ex).__name__ + ': ' + ' '.join(str(ex).split())[:1500])",
             "    print('<<' + 'TIME>>', walltime() - t0)",
             "    raise SystemExit(0)",
             "print('<<' + 'ANS>>', str(_casbench_answer))", "print('<<' + 'TIME>>', t1 - t0)",
             # a list answer (FriCAS: one antiderivative per case of a parameter's sign) is evaluated form by form
             "_casbench_forms = list(_casbench_answer) if isinstance(_casbench_answer, (list, tuple)) else [_casbench_answer]",
             "print('<<' + 'NFORMS>>', len(_casbench_forms))",
             "for _casbench_k, _casbench_form in enumerate(_casbench_forms, 1):",
             "    if len(_casbench_forms) > 1: print('<<' + 'FORM%d>>' % _casbench_k, str(_casbench_form))"]
    xs = check_points(integrand, params)
    for (i, xv) in enumerate(xs)
        point = sage_point(xv)
        push!(lines, "for _casbench_k, _casbench_form in enumerate(_casbench_forms, 1):\n" *
                     "    _casbench_mark = 'V$i' if _casbench_k == 1 else 'V$(i)_%d' % _casbench_k\n" *
                     "    try:\n        _casbench_value = CC(SR(_casbench_form).subs({$var: $point" * (isempty(pt) ? "" : ", " * pt) * "}))\n" *
                     "        print('<<' + _casbench_mark + '>>', str(_casbench_value))\n" *
                     "    except Exception as ex:\n        print('<<' + _casbench_mark + '>>', 'fail')")
    end
    txt, answer_ns = run_sage(join(lines, "\n") * "\n"; capture_answer=true)
    ans = marker(txt, "<<ANS>>")
    ans === nothing && error("sage gave no answer: " * last(strip(replace(txt, "\n" => " ")), 300))
    # an exception inside Sage is an error of the interface (e.g. the pexpect giac interface cannot parse an answer that
    # giac prints with a warning), unless the system declares that it cannot integrate (then the worker says unsolved)
    startswith(ans, "sage_error:") && !occursin(r"not implemented|NotImplemented|cannot|unable", ans) && error(ans)
    values_of(suffix) = (vals = Dict{ComplexF64,ComplexF64}();
        for (i, xv) in enumerate(xs)
            v = marker(txt, "<<V$i$suffix>>")
            (v === nothing || v == "fail") && continue
            c = parse_sage_complex(v)
            c === nothing || (vals[xv] = c)
        end; vals)
    t = marker(txt, "<<TIME>>")
    elapsed = t === nothing ? NaN : parse(Float64, t)
    nf = marker(txt, "<<NFORMS>>")
    nforms = nf === nothing ? 1 : something(tryparse(Int, nf), 1)
    alts = nforms > 1 ? [SageAnswer(something(marker(txt, "<<FORM$k>>"), ""), values_of(k == 1 ? "" : "_$k"), elapsed, answer_ns)
                         for k in 1:nforms] : SageAnswer[]
    SageAnswer(ans, values_of(""), elapsed, answer_ns, alts)
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
        # Sage's giac interface raises on any output that contains "error" (giac._eval_line), and Giac prints over Q
        # the note "error probability is less than 1e-15" of its probabilistic algorithm: the basis was computed,
        # but before 2026-11-25 every such case was recorded as an error ("sage gave no basis"). The command is
        # evaluated with the base Expect._eval_line, and a long command through a file as Sage's own
        # _eval_line_using_file does (whose read command would otherwise go through giac._eval_line again); the
        # process start and the timing are the same. An output line that mentions an error other than that note
        # still raises.
        ["from sage.interfaces.expect import Expect",
         "giac.eval('threads:=1')",          # one Giac thread, as in every Giac column (docs/benches.md), before the timed call
         "Expect._eval_line(giac, 'casbench_B:=\"casbench_unset\":;', allow_use_file=False)",   # no stale basis from the previous case
         "_casbench_cmd = 'casbench_B:=gbasis(" * (p == 0 ? L : L * " % $p") * ",$V,revlex)'",
         "t0 = walltime()",
         "if giac._eval_using_file_cutoff and len(_casbench_cmd) > giac._eval_using_file_cutoff:",
         "    with open(giac._local_tmpfile(), 'w') as _casbench_file:",
         "        _casbench_file.write(_casbench_cmd + '\\n')",
         "    _casbench_out = Expect._eval_line(giac, giac._read_in_file_command(giac._local_tmpfile()), allow_use_file=False)",
         "else:",
         "    _casbench_out = Expect._eval_line(giac, _casbench_cmd, allow_use_file=False)",
         "t1 = walltime()",
         "_casbench_errors = [l for l in _casbench_out.splitlines() if 'error' in l.lower() and 'error probability' not in l.lower()]",
         "if _casbench_errors: raise RuntimeError('giac: ' + ' | '.join(_casbench_errors)[:300])",
         "if Expect._eval_line(giac, 'type(casbench_B)', allow_use_file=False).strip().splitlines()[-1] == 'string': raise RuntimeError('giac gave no basis: ' + ' '.join(_casbench_out.split())[:300])",
         "B = giac('casbench_B')",
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
# an unevaluated integral is printed integrate(...) by Sage's own front end and integral(...) when it comes back
# from FriCAS (algorithm='fricas'), as the direct FriCAS adapter recognises; before 2026-11-25 the second form
# was missed and such answers were checked, then recorded as unverified instead of unsolved
UNSOLVED(op, out) = out isa SageAnswer && occursin(r"integrate\(|\bintegral\(|sage_error: .*(not implemented|NotImplemented|cannot|unable)", out.text)
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
                    if !occursin(Regex("\\b" * m.match * "\\("), f) && !(m.match in ("pi", "I", "E"))])
    symbols = join(unique([variable; words]), " ")
    lines = ["var(" * repr(symbols) * ")", "_casbench_integrand = SR(" * f * ")", "_casbench_answer = SR(" * answer * ")"]
    if SAGE_ALGORITHM == "giac"
        push!(lines, "r = giac('simplify(diff((' + str(giac(_casbench_answer)) + '),' + str(giac(" * variable * ")) + ')-(' + str(giac(_casbench_integrand)) + '))')")
    elseif SAGE_ALGORITHM == "maxima"
        push!(lines, "r = (_casbench_answer._maxima_().diff(" * variable * "._maxima_()) - _casbench_integrand._maxima_()).radcan().ratsimp()")
    elseif SAGE_ALGORITHM == "fricas"
        push!(lines, "r = (fricas(_casbench_answer).D(fricas(" * variable * ")) - fricas(_casbench_integrand)).simplify()")
    elseif SAGE_ALGORITHM == "sympy"
        push!(lines, "import sympy as sp")
        push!(lines, "r = sp.simplify(sp.diff(_casbench_answer._sympy_(), sp.Symbol(" * repr(variable) * ")) - _casbench_integrand._sympy_())")
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
