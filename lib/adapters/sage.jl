# SageMath adapter (benches F and G), as a subprocess: one `sage script.sage`
# per case. The thin files sage_<algorithm>.jl set SAGE_ALGORITHM and include
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

struct SageAnswer
    text::String
    values::Dict{Float64,ComplexF64}
    elapsed::Float64
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

check_points() = (pts = Main.FPOINTS; h = 1e-5; [x0 + s * h for x0 in pts for s in (-1, 1)])

function run_sage(script::String)
    path = tempname() * ".sage"
    write(path, script)
    out = IOBuffer()
    try
        run(pipeline(`$SAGE $path`; stdout = out, stderr = devnull))
    finally
        rm(path; force = true)
        rm(path * ".py"; force = true)
    end
    String(take!(out))
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

function INTEGRATE_TEXT(integrand::String, var::String)
    f = Mapleish.translate(integrand, :sage)
    syms = unique([m.match for m in eachmatch(r"\b[A-Za-z_][A-Za-z_0-9]*\b", f)
                   if !occursin(m.match * "(", f) && !(m.match in ("pi", "I", "e", "E"))])
    params = [k for (k, v) in Main.FPARAMS if string(k) in syms]
    pt = join(["$k: $(v)" for (k, v) in Main.FPARAMS if k in params], ", ")
    lines = ["var('" * join(unique([var; string.(params)]), " ") * "')",
             "f = $f", "t0 = walltime()",
             "try:",
             SAGE_ALGORITHM == "giac" ? "    Fg = giac(f).integrate(giac($var))\n    t1 = walltime()\n    try:\n        F = Fg.sage()\n    except Exception as ex:\n        F = SR(str(Fg))" :
                                        "    F = integrate(f, $var, algorithm='$SAGE_ALGORITHM')\n    t1 = walltime()",
             "except Exception as ex:",
             "    print('<<' + 'ANS>>', 'sage_error: ' + str(ex)[:200])",
             "    print('<<' + 'TIME>>', walltime() - t0)",
             "    raise SystemExit(0)",
             "print('<<' + 'ANS>>', str(F))", "print('<<' + 'TIME>>', t1 - t0)"]
    for (i, xv) in enumerate(check_points())
        push!(lines, "try:\n    v = CC(F.subs({$var: $xv" * (isempty(pt) ? "" : ", " * pt) * "}))\n    print('<<' + 'V$i>>', str(v))\nexcept Exception as ex:\n    print('<<' + 'V$i>>', 'fail')")
    end
    txt = run_sage(join(lines, "\n") * "\n")
    ans = marker(txt, "<<ANS>>")
    ans === nothing && error("sage gave no answer: " * last(strip(replace(txt, "\n" => " ")), 200))
    vals = Dict{Float64,ComplexF64}()
    for (i, xv) in enumerate(check_points())
        v = marker(txt, "<<V$i>>")
        (v === nothing || v == "fail") && continue
        c = parse_sage_complex(v)
        c === nothing || (vals[xv] = c)
    end
    t = marker(txt, "<<TIME>>")
    SageAnswer(ans, vals, t === nothing ? NaN : parse(Float64, t))
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

const OPS = Dict{Symbol,Any}(:integrate_text => INTEGRATE_TEXT, :groebner => GROEBNER)
EVAL(ex, vals) = ex isa SageAnswer ? get(ex.values, vals[:x], nothing) : (ex isa Number ? ex : nothing)
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
