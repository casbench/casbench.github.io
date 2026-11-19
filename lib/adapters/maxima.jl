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
    elapsed::Float64                   # seconds of the integrate call inside Maxima
end
const REPEATS = 1                      # one process per case; the warm time is the in-process time
Base.string(a::MaximaAnswer) = a.text

# points of the check (FPOINTS, FPARAMS and h of F_integration/problems.jl, read at call time)
check_points() = (pts = Main.FPOINTS; h = 1e-5; [x0 + s * h for x0 in pts for s in (-1, 1)])
# only the parameters the integrand uses
param_list(integrand, params) = ["$k=$(v)" for (k, v) in params if occursin(Regex("\\b$k\\b"), integrand)]

function run_maxima(script::String)
    out = IOBuffer()
    cmd = pipeline(`$MAXIMA --very-quiet --batch-string=$script`; stdout = out, stderr = devnull)
    run(cmd)
    String(take!(out))
end

function INTEGRATE_TEXT(integrand::String, var::String, params = Main.FPARAMS)
    f = Mapleish.translate(integrand, :maxima)
    xs = check_points()
    # the batch echoes its input: the markers are assembled by concat so that they only occur in the output
    plist = param_list(integrand, params)
    # the sign of each parameter is assumed as its fixed value has it (a > 0, or m < 0 for a negative candidate value)
    signs = ["$k$(v > 0 ? ">" : "<")0" for (k, v) in params if v != 0 && occursin(Regex("\\b$k\\b"), integrand)]
    assumptions = isempty(signs) ? "" : "assume(" * join(signs, ",") * ")\$"
    # questions Maxima asks in batch mode (asksign, askinteger, ...) are answered by an oracle that evaluates the
    # expression asked about at the fixed values of the parameters and at x = 0.57 (the middle check point)
    subst = join(["$k=$(v)" for (k, v) in params] ∪ ["x=0.57"], ",")
    oracle = ["oracle_(e_, t_) := block([v_], v_: errcatch(float(subst([$subst], e_))), " *
              "if length(v_) = 0 or not numberp(first(v_)) then (if ssearch(\"integer\", t_) # false or ssearch(\"even\", t_) # false or ssearch(\"odd\", t_) # false then 'no else 'pos) " *
              "else block([w_: first(v_)], if ssearch(\"integer\", t_) # false then (if integerp(w_) then 'yes else 'no) " *
              "elseif ssearch(\"even\", t_) # false then (if evenp(w_) then 'yes else 'no) elseif ssearch(\"odd\", t_) # false then (if oddp(w_) then 'yes else 'no) " *
              "elseif ssearch(\"zero or nonzero\", t_) # false then (if w_ = 0 then 'zero else 'nonzero) " *
              "else (if w_ > 0 then 'pos elseif w_ < 0 then 'neg else 'zero)))\$",
              ":lisp (defun retrieve (msg flag &aux tem) (declare (ignore flag tem)) (let ((e (find-if-not #'stringp (cdr msg))) (text (apply #'concatenate 'string (mapcar (lambda (z) (if (stringp z) z \"\")) (cdr msg))))) (mfuncall '\$oracle_ e text)))"]
    lines = ["display2d:false\$", "ratprint:false\$", "linel:1000000\$", oracle..., assumptions, "t0_: elapsed_real_time()\$",
             "res_: errcatch(integrate($f, $var))\$", "res_: if length(res_) = 0 then 'maxima_error else first(res_)\$",
             "print(concat(\"<<T\", \"IME>>\"), string(float(elapsed_real_time() - t0_)))\$",
             "print(concat(\"<<AN\", \"S>>\"), string(res_))\$"]
    for (i, xv) in enumerate(xs)
        args = join(["$var=$xv"; plist; "numer"], ",")
        push!(lines, "print(concat(\"<<V\", $i, \">>\"), string(float(rectform(ev(res_, $args)))))\$")
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
    mt = match(r"<<TIME>>\s*([0-9.eE+-]+)", txt)
    MaximaAnswer(ans, vals, mt === nothing ? NaN : parse(Float64, mt[1]))
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
UNSOLVED(op, out) = out isa MaximaAnswer && occursin(r"integrate\(|'integrate|maxima_error", out.text)
CLEARCACHE() = nothing
function VERSIONS()
    v = try
        strip(read(`$MAXIMA --version`, String))
    catch
        "unknown"
    end
    ["Maxima" => replace(v, r"^Maxima\s*" => "")]
end
