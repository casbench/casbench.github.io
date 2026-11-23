# GrobX 0.73.3 (GPL-3.0-only): a Python process per call, with its own
# in-process wall time. The common G check is performed separately in Julia.
const SYSTEM = "GrobX"
const VAR = Dict{Symbol,Any}()
const REPEATS = 1
const GROBX_PYTHON = get(ENV, "GROBX_PYTHON", get(ENV, "JULIA_PYTHONCALL_EXE", "python3"))
const GROBX_VERSION = try
    strip(read(pipeline(`timeout -k 2 30 $GROBX_PYTHON -c 'import grobx; print(grobx.__version__)'`; stderr=devnull), String))
catch
    "unavailable"
end
const GROBX_PYTHON_VERSION = try
    strip(read(pipeline(`timeout -k 2 30 $GROBX_PYTHON --version`; stderr=devnull), String))
catch
    "unknown"
end
isdefined(Main, :Poly) || include(joinpath(@__DIR__, "..", "poly.jl"))

struct GrobxBasis
    polys::Vector{String}
    elapsed::Float64
    process_peak_rss_kib::Int
end
Base.string(b::GrobxBasis) = string(b.polys)
Base.isempty(b::GrobxBasis) = isempty(b.polys)

function grobx_modp_string(s::String, vars::Vector{String}, p::Int)
    f = Poly.parse_poly(s, vars)
    terms = String[]
    for (m, c) in sort!(collect(f); by=x -> Tuple(first(x)))
        mono = join(("$(vars[i])^$(m[i])" for i in eachindex(m) if m[i] > 0), "*")
        coeff = Poly.modp(c, p)
        coeff == 0 && continue
        push!(terms, string(coeff, isempty(mono) ? "" : "*" * mono))
    end
    isempty(terms) ? "0" : join(terms, "+")
end

function GROEBNER(polys::Vector{String}, vars::Vector{String}, p::Int)
    input = join(vars, ",") * "\n" * string(p) * "\n" *
            join((p == 0 ? replace(s, "//" => "/") : grobx_modp_string(s, vars, p) for s in polys), ",\n") * "\n"
    log_input!("grobx.groebner(instance, order='grevlex', threads=1, seed=0, checker=None)\ninstance:\n" * input)
    path = tempname()
    write(path, input)
    stdout = IOBuffer(); stderr = IOBuffer()
    try
        cmd = `$GROBX_PYTHON $(joinpath(@__DIR__, "grobx_runner.py")) $path`
        run(pipeline(cmd; stdout=stdout, stderr=stderr))
    catch e
        msg = strip(String(take!(stderr)))
        error("GrobX process failed: " * (isempty(msg) ? sprint(showerror, e) : last(msg, 500)))
    finally
        rm(path; force=true)
    end
    txt = String(take!(stdout))
    timed = match(r"<<TIME>>\s*([0-9.eE+-]+)", txt)
    rss = match(r"<<RSS_KIB>>\s*(\d+)", txt)
    timed === nothing && error("GrobX returned no timing")
    rss === nothing && error("GrobX returned no process memory")
    gs = [strip(m[1]) for m in eachmatch(r"<<G>>\s*(.*)", txt)]
    isempty(gs) && !occursin("<<STOP>>", txt) && error("GrobX returned no basis")
    GrobxBasis(gs, parse(Float64, timed[1]), parse(Int, rss[1]))
end
const OPS = Dict{Symbol,Any}(:groebner => GROBX_VERSION == "0.73.3" ? GROEBNER : missing)
EVAL(ex, vals) = ex isa Number ? ex : nothing
NTERMS(ex) = 1
NFACTORS(ex) = 1
UNSOLVED(op, out) = out isa GrobxBasis && isempty(out.polys)
CLEARCACHE() = nothing
VERSIONS() = ["GrobX" => GROBX_VERSION, "GrobX Python" => GROBX_PYTHON_VERSION, "GrobX Python executable" => GROBX_PYTHON]
