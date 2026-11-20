# Compute Engine adapter (the CortexJS Compute Engine, a JavaScript symbolic
# engine working on MathJSON), as a subprocess: one Node.js process per worker
# (lib/adapters/ce_server.mjs), fed one JSON request per case. The Maple-like
# text of the benches is parsed to a Julia expression (lib/mapleish.jl) and
# written as MathJSON; answers come back as LaTeX with the numeric values the
# checks need. Needs `node` on PATH and COMPUTE_ENGINE_DIR pointing at the
# unpacked npm package (the Nix toolchain provides both).
const SYSTEM = "Compute Engine"
const VAR = Dict{Symbol,Any}()
const REPEATS = 1

isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "mapleish.jl"))

const NODE = get(ENV, "NODE", "node")
const CE_DIR = get(ENV, "COMPUTE_ENGINE_DIR", "")

# ---- MathJSON from the Maple-like text --------------------------------------------------------------
const CE_FUNCS = Dict(:sin => "Sin", :cos => "Cos", :tan => "Tan", :cot => "Cot", :sec => "Sec", :csc => "Csc",
                      :sinh => "Sinh", :cosh => "Cosh", :tanh => "Tanh", :coth => "Coth", :sech => "Sech", :csch => "Csch",
                      :asin => "Arcsin", :acos => "Arccos", :atan => "Arctan", :acot => "Arccot", :asec => "Arcsec", :acsc => "Arccsc",
                      :asinh => "Arcsinh", :acosh => "Arccosh", :atanh => "Arctanh", :acoth => "Arccoth", :asech => "Arcsech", :acsch => "Arccsch",
                      :exp => "Exp", :log => "Ln", :sqrt => "Sqrt", :abs => "Abs", :gamma => "Gamma", :erf => "Erf", :erfc => "Erfc")
jsonstr(s) = "\"" * replace(string(s), "\\" => "\\\\", "\"" => "\\\"") * "\""
function mathjson(ex)
    ex isa Integer && return string(ex)
    ex isa Rational && return "[\"Rational\", $(numerator(ex)), $(denominator(ex))]"
    ex isa AbstractFloat && return repr(Float64(ex))
    ex isa Symbol && return ex == :pi ? "\"Pi\"" : ex == :im ? "\"ImaginaryUnit\"" : jsonstr(ex)
    ex isa Expr || error("unsupported node $(typeof(ex))")
    if ex.head == :call
        f, args = ex.args[1], ex.args[2:end]
        if f == :+
            return "[\"Add\", " * join(mathjson.(args), ", ") * "]"
        elseif f == :*
            return "[\"Multiply\", " * join(mathjson.(args), ", ") * "]"
        elseif f == :- && length(args) == 1
            return "[\"Negate\", " * mathjson(args[1]) * "]"
        elseif f == :-
            return "[\"Subtract\", " * join(mathjson.(args), ", ") * "]"
        elseif f == :/
            return "[\"Divide\", " * mathjson(args[1]) * ", " * mathjson(args[2]) * "]"
        elseif f == :^
            return "[\"Power\", " * mathjson(args[1]) * ", " * mathjson(args[2]) * "]"
        elseif haskey(CE_FUNCS, f)
            return "[" * jsonstr(CE_FUNCS[f]) * ", " * join(mathjson.(args), ", ") * "]"
        else
            error("unsupported function $f")
        end
    end
    error("unsupported expression $(ex.head)")
end
to_mathjson(text::String) = mathjson(Mapleish.julia_expr(text))

# ---- the persistent Node process ----------------------------------------------------------------------
const CE_PROC = Ref{Any}(nothing)
function ce_process()
    p = CE_PROC[]
    if p === nothing || !process_running(p)
        isempty(CE_DIR) && error("COMPUTE_ENGINE_DIR is not set")
        p = open(addenv(`$NODE $(joinpath(@__DIR__, "ce_server.mjs"))`, "COMPUTE_ENGINE_DIR" => CE_DIR), "r+")
        t0 = time()
        while time() - t0 < 60
            l = readline(p)
            (l == "<<READY>>" || (!process_running(p) && eof(p))) && break
        end
        CE_PROC[] = p
    end
    p
end

struct CEAnswer
    text::String                       # LaTeX of the result
    values::Dict{Float64,ComplexF64}   # x => value at the check points (when requested)
    number::Union{Nothing,ComplexF64}  # the value for op eval
    cvalues::Vector{Float64}           # values of the compiled function (op codegen)
    elapsed::Float64
end
Base.string(a::CEAnswer) = a.text

parse_num(s) = (t = strip(s); t == "fail" ? nothing :
    (m = match(r"^([^,]+),(.+)$", t); m !== nothing ? ComplexF64(parse(Float64, m[1]), parse(Float64, m[2])) :
     (v = tryparse(Float64, t); v === nothing ? nothing : ComplexF64(v))))

function request(json::String)
    log_input!(json)
    p = ce_process()
    println(p, json); flush(p)
    lines = String[]
    while true
        (eof(p) && !process_running(p)) && break
        l = readline(p)
        l == "<<END>>" && break
        push!(lines, l)
    end
    get(ENV, "BENCH_DEBUG", "0") == "1" && (println(stderr, "--- ce request\n", json, "\n--- ce answer\n", join(lines, "\n")); flush(stderr))
    marker(m) = (i = findfirst(l -> startswith(l, m * " "), lines); i === nothing ? nothing : strip(lines[i][length(m)+2:end]))
    ans = marker("<<ANS>>")
    ans === nothing && error("compute engine gave no answer: " * first(join(lines, " "), 200))
    startswith(ans, "ce_error:") && error(ans)
    t = marker("<<TIME>>")
    vals = Dict{Float64,ComplexF64}()
    for l in lines
        m = match(r"^<<V(\d+)>> (.*)$", l)
        m === nothing && continue
        v = parse_num(m[2]); v === nothing && continue
        vals[CHECK_XS[parse(Int, m[1])]] = v
    end
    n = marker("<<N>>")
    cvals = Float64[]
    for l in lines
        m = match(r"^<<C(\d+)>> (.*)$", l)
        m === nothing && continue
        v = tryparse(Float64, strip(m[2])); push!(cvals, v === nothing ? NaN : v)
    end
    ct = marker("<<CTIME>>")
    CEAnswer(ans, vals, n === nothing ? nothing : parse_num(n), cvals,
             ct !== nothing ? parse(Float64, ct) : (t === nothing || t == "nan" ? NaN : parse(Float64, t)))
end

# the six points of the integration check (F, H): x0 ± h for the three x0 of lib/integration_check.jl
const CHECK_XS = Float64[]
function points_json(params)
    empty!(CHECK_XS)
    for x0 in Main.FPOINTS, s in (-1, 1)
        push!(CHECK_XS, x0 + s * 1e-5)
    end
    "[" * join(["{" * join(["\"$k\": $v" for (k, v) in params] ∪ ["\"x\": $xv"], ", ") * "}" for xv in CHECK_XS], ", ") * "]"
end

function INTEGRATE_TEXT(integrand::String, var::String, params = Main.FPARAMS)
    used = Dict(k => v for (k, v) in params if occursin(Regex("\\b$k\\b"), integrand))
    request("{\"op\": \"integrate\", \"expr\": " * to_mathjson(integrand) * ", \"var\": " * jsonstr(var) * ", \"points_eval\": " * points_json(used) * "}")
end
# the numeric check of bench I evaluates the answer at IPOINT (or at (1.1, 0.7, 1.3) for the derivative): one point
function ipoint_json(pt)
    empty!(CHECK_XS); push!(CHECK_XS, Float64(pt[:x]))
    "[{" * join(["\"$k\": $(Float64(v))" for (k, v) in pt], ", ") * "}]"
end
ipoint() = isdefined(Main, :IPOINT) ? Main.IPOINT : Dict(:x => 0.37, :y => 0.83, :z => 1.21, :w => 0.61, :a => 0.9, :b => 1.3, :c => 0.7)
EXPAND_TEXT(s) = request("{\"op\": \"expand\", \"expr\": " * to_mathjson(s) * ", \"points_eval\": " * ipoint_json(ipoint()) * "}")
EXPAND_DIFF_TEXT(s, v) = request("{\"op\": \"expand_diff\", \"expr\": " * to_mathjson(s) * ", \"var\": " * jsonstr(v) *
                                 ", \"points_eval\": " * ipoint_json(Dict(:x => 1.1, :y => 0.7, :z => 1.3)) * "}")
SUBS_TEXT(s, rules) = request("{\"op\": \"subs\", \"expr\": " * to_mathjson(s) * ", \"rules\": {" *
                              join([jsonstr(l) * ": " * to_mathjson(r) for (l, r) in rules], ", ") * "}, \"points_eval\": " * ipoint_json(ipoint()) * "}")
function EVAL_TEXT(s, pt::Dict)
    rules = "{" * join([jsonstr(k) * ": " * repr(Float64(v)) for (k, v) in pt], ", ") * "}"
    a = request("{\"op\": \"eval\", \"expr\": " * to_mathjson(s) * ", \"rules\": " * rules * "}")
    a.number === nothing ? nothing : (abs(imag(a.number)) < 1e-12 ? real(a.number) : a.number)
end
function CODEGEN_TEXT(s, vars, points)
    pts = "[" * join(["{" * join(["\"$(vars[i])\": $(p[i])" for i in eachindex(vars)], ", ") * "}" for p in points], ", ") * "]"
    a = request("{\"op\": \"codegen\", \"expr\": " * to_mathjson(s) * ", \"points\": " * pts * "}")
    (values = a.cvalues, elapsed = a.elapsed, text = "compile(): $(length(a.cvalues)) calls")
end

const OPS = Dict{Symbol,Any}(
    :integrate_text => INTEGRATE_TEXT,
    :expand_text => EXPAND_TEXT, :expand_diff_text => EXPAND_DIFF_TEXT, :subs_text => SUBS_TEXT,
    :eval_text => EVAL_TEXT, :codegen_text => CODEGEN_TEXT,
    :series_text => missing,                    # no Taylor series
)
EVAL(ex, vals) = ex isa CEAnswer ? get(ex.values, vals[:x], nothing) : (ex isa Number ? ex : nothing)
NTERMS(ex) = ex isa CEAnswer ? count("+", ex.text) + 1 : 1     # terms of a LaTeX sum (the engine prints a flat sum)
NFACTORS(ex) = 1
UNSOLVED(op, out) = out isa CEAnswer && occursin(r"\\int|\\mathrm\{d\}|\\operatorname\{D\}|ce_error", out.text)
CLEARCACHE() = nothing
function VERSIONS()
    v = try
        m = match(r"\"version\":\s*\"([^\"]+)\"", read(joinpath(CE_DIR, "package.json"), String)); m === nothing ? "unknown" : m[1]
    catch
        "unknown"
    end
    n = try strip(read(`$NODE --version`, String)) catch; "unknown" end
    ["compute-engine" => v, "node" => n]
end
