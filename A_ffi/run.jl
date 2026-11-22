# Bench A: cost of one call per dispatch level in Giac.jl.
#
#   julia --project=envs/giac A_ffi/run.jl [OUT_TSV]
#
# Levels (same mathematical result at every level, checked by string equality):
#   binding      the CxxWrap binding called on a cached C++ Gen, result not wrapped
#                (tier 1 function such as giac_sin, or apply_func1 by name)
#   tier1        Base.sin(::GiacExpr) etc.: Julia wrapper over the tier-1 binding
#                (only for the commands that have a tier-1 binding)
#   invoke_fast  invoke_cmd(:cmd, expr): dispatch by name, Gen passed directly
#   invoke_str   the same call with the string path forced
#                (GIAC_INVOKE_CMD_STRING_PATH): print, concatenate, reparse
#   giac_eval    giac_eval("cmd(...)") on a pre-built string
#
# Times are the minimum over ROUNDS rounds of (loop of N calls)/N, in
# microseconds. Inputs rotate through a small pool so that Giac's memoisation of
# an identical repeated call does not dominate the measurement; the pool is the
# same for every level.

include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
using Giac
using Giac.GiacCxxBindings

const OUT = length(ARGS) >= 1 ? ARGS[1] : joinpath(results_dir(), "A_ffi_giac.tsv")
const ROUNDS = 7
const N = 2000

@giac_var x y z

function with_string_path(f)
    ENV["GIAC_INVOKE_CMD_STRING_PATH"] = "1"
    Giac._refresh_fastpath_flag!()
    try
        f()
    finally
        delete!(ENV, "GIAC_INVOKE_CMD_STRING_PATH")
        Giac._refresh_fastpath_flag!()
    end
end

function bench_loop(f, pool)
    m = length(pool)
    for i in 1:200
        f(pool[mod1(i, m)])
    end
    best = Inf
    for _ in 1:ROUNDS
        GC.gc()
        t0 = time_ns()
        for i in 1:N
            f(pool[mod1(i, m)])
        end
        best = min(best, (time_ns() - t0) / 1e3 / N)
    end
    best
end

# A case: command name, a pool of GiacExpr inputs, the tier-1 binding (or
# nothing), and the extra argument (or nothing)
struct Case
    name::String
    cmd::Symbol
    pool::Vector{GiacExpr}
    tier1::Union{Nothing,Function}      # e.g. GiacCxxBindings.giac_sin
    julia_fn::Union{Nothing,Function}   # e.g. Base.sin
    extra::Union{Nothing,GiacExpr}
end

poly_pool = [x^4 - 1, x^8 - 1, x^12 - 1, x^2 * y^2 - 1, x^6 - y^6, x^10 + x^5 + 1,
             x^7 - x^6 - 6x^5 + 2x^4 + 3x^3 - 9x^2 - 4x + 4, x^16 - 1]
expand_pool = [(x + y)^5, (x + y)^10, (x + y + z)^6, (x + 1)^20, (x + 2y)^8, (x - y)^12, (x + y + 1)^5, (2x + 3y)^7]
small_pool = [x, x + 1, 2x, x^2, x * y, x - y, 3x + 2, x / 2]

cases = [
    Case("sin(x) [trivial, tier 1]", :sin, small_pool, GiacCxxBindings.giac_sin, Base.sin, nothing),
    # normal and diff have tier-1 bindings, but no public method is wired to them
    # (Giac.Commands.normal / diff go through invoke_cmd), so the tier-1 wrapper
    # is called through the internal helper that Base.sin uses
    Case("normal(expr) [tier 1]", :normal, [(x + 1)^2, (x - y)^2, x^2 + 2x + 1, (x + 1) * (x - 1), x * (x + 1), (x + y)^2, 2(x + 1), (x + 2)^2],
         GiacCxxBindings.giac_normal, e -> Giac._tier1_or_fallback(Giac._giac_normal_tier1, :normal, e), nothing),
    Case("diff(expr, x) [tier 1, binary]", :diff, [x^5 * sin(x), x^3, exp(x) * x, sin(x) * cos(x), x^2 + y, log(x) * x, x^4 - x, x * y^2],
         GiacCxxBindings.giac_diff, (e, v) -> Giac._tier1_or_fallback_binary(Giac._giac_diff_tier1, :diff, e, v), x),
    Case("factor(poly)", :factor, poly_pool, nothing, nothing, nothing),
    Case("expand(poly)", :expand, expand_pool, nothing, nothing, nothing),
]

isfile(OUT) && error("refusing to replace existing results $OUT; choose a new BENCH_HOST")

write_machine_info(joinpath(dirname(abspath(OUT)), "machine.txt"),
                   ["bench" => "A_ffi", "Giac.jl" => string(pkgversion(Giac)),
                    "GIAC_jll" => string(pkgversion(Giac.GIAC_jll)),
                    "libgiac_julia_jll" => string(pkgversion(Giac.libgiac_julia_jll)),
                    "giac_version" => string(giac_eval("version()"))])

for (ci, c) in enumerate(cases)
    gens = [Giac._get_gen_or_eval(e) for e in c.pool]
    strs = c.extra === nothing ? [string(c.cmd, "(", string(e), ")") for e in c.pool] :
                                 [string(c.cmd, "(", string(e), ",", string(c.extra), ")") for e in c.pool]
    extra_gen = c.extra === nothing ? nothing : Giac._get_gen_or_eval(c.extra)
    name = string(c.cmd)

    # reference results through giac_eval, and a check that every level agrees
    ref = [string(giac_eval(s)) for s in strs]
    function verify(level, f)
        for (i, e) in enumerate(c.pool)
            r = f(e)
            s = r isa GiacExpr ? string(r) : string(GiacExpr(Giac._make_gen_ptr(r)))
            s == ref[i] || error("level $level disagrees on $(strs[i]): $s vs $(ref[i])")
        end
    end

    levels = Pair{String,Function}[]
    # binding: tier-1 binding if any, else apply_func1/apply_func2 by name
    idx = Dict(objectid(e) => i for (i, e) in enumerate(c.pool))
    if c.tier1 !== nothing
        if extra_gen === nothing
            push!(levels, "binding" => e -> c.tier1(gens[idx[objectid(e)]]))
        else
            push!(levels, "binding" => e -> c.tier1(gens[idx[objectid(e)]], extra_gen))
        end
    else
        push!(levels, "binding" => e -> GiacCxxBindings.apply_func1(name, gens[idx[objectid(e)]]))
    end
    if c.julia_fn !== nothing
        push!(levels, "tier1" => (extra_gen === nothing ? (e -> c.julia_fn(e)) : (e -> c.julia_fn(e, c.extra))))
    end
    push!(levels, "invoke_fast" => (extra_gen === nothing ? (e -> invoke_cmd(c.cmd, e)) : (e -> invoke_cmd(c.cmd, e, c.extra))))
    push!(levels, "invoke_str" => (extra_gen === nothing ? (e -> invoke_cmd(c.cmd, e)) : (e -> invoke_cmd(c.cmd, e, c.extra))))
    push!(levels, "giac_eval" => e -> giac_eval(strs[idx[objectid(e)]]))

    for (lname, f) in levels
        t = if lname == "invoke_str"
            with_string_path() do
                verify(lname, f)
                bench_loop(f, c.pool)
            end
        else
            verify(lname, f)
            bench_loop(f, c.pool)
        end
        append_record(OUT, Record("A_ffi", "Giac.jl", ci, c.name, lname, "verified", NaN, t * 1e-6,
                                  "", "min over $ROUNDS rounds of $N calls; pool of $(length(c.pool)) inputs"))
        println(rpad(c.name, 36), rpad(lname, 14), round(t; digits = 2), " us/call")
    end
end
