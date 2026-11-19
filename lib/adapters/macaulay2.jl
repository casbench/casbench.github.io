# Macaulay2 adapter (bench G), as a subprocess: one `M2 --script` per case,
# which computes the reduced Gröbner basis (gens gb, degrevlex, the default
# monomial order of M2 rings) and prints each generator and the wall time of
# the computation. Needs `M2` on PATH (the Nix toolchain provides it).
const SYSTEM = "Macaulay2"
const VAR = Dict{Symbol,Any}()
const REPEATS = 1

isdefined(Main, :Poly) || include(joinpath(@__DIR__, "..", "poly.jl"))

const M2 = get(ENV, "M2", "M2")
const CASE_LIMIT = get(ENV, "BENCH_CASE_TIMEOUT", "600")   # seconds; a subprocess never outlives the case

struct M2Basis
    polys::Vector{String}
    elapsed::Float64
end
Base.string(b::M2Basis) = string(b.polys)
Base.length(b::M2Basis) = length(b.polys)
Base.iterate(b::M2Basis, st...) = iterate(b.polys, st...)
Base.isempty(b::M2Basis) = isempty(b.polys)

function GROEBNER(polys::Vector{String}, vars::Vector{String}, p::Int)
    ring = p == 0 ? "QQ" : "ZZ/$p"
    lines = ["R = $ring[" * join(vars, ",") * ", MonomialOrder => GRevLex];",
             "I = ideal(" * join([replace(s, "//" => "/") for s in polys], ", ") * ");",
             "t0 = cpuTime();", "G = flatten entries gens gb I;", "t1 = cpuTime();",
             "print(\"<<TIME>> \" | toString(t1 - t0));",
             "scan(G, g -> print(\"<<G>> \" | toString g));"]
    path = tempname() * ".m2"
    write(path, join(lines, "\n") * "\n")
    out = IOBuffer()
    try
        run(pipeline(`timeout -k 5 $CASE_LIMIT $M2 --script $path`; stdout = out, stderr = devnull))
    finally
        rm(path; force = true)
    end
    txt = String(take!(out))
    gs = [strip(m[1]) for m in eachmatch(r"<<G>>\s*(.*)", txt)]
    isempty(gs) && error("M2 gave no basis: " * last(strip(replace(txt, "\n" => " ")), 200))
    mt = match(r"<<TIME>>\s*([0-9.eE+-]+)", txt)
    M2Basis(gs, mt === nothing ? NaN : parse(Float64, mt[1]))
end

const OPS = Dict{Symbol,Any}(:groebner => GROEBNER)
EVAL(ex, vals) = ex isa Number ? ex : nothing
NTERMS(ex) = 1
NFACTORS(ex) = 1
UNSOLVED(op, out) = out isa M2Basis && isempty(out.polys)
CLEARCACHE() = nothing
function VERSIONS()
    v = try
        strip(read(pipeline(`$M2 --version`; stderr = devnull), String))
    catch
        "unknown"
    end
    ["Macaulay2" => first(v, 60)]
end
