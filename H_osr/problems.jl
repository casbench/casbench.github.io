# Bench H: the integration rules of OpenSymbolicRules v1 as problems
# (H_osr/rules.tsv, converted from osr/Integration/v1/integration.osr.json by
# H_osr/convert.py; see README.md).
#
# Each rule gives one problem: ∫ integrand dx with the rule's parameters at
# the first set of fixed values that satisfies the rule's conditions (plain
# values first, then integer values where the rule asks for integers, then a
# set with negative values). Every adapter maps :integrate_text to
# (integrand::String, var::String, params) -> answer, as in bench F. The check
# is the one of bench F (lib/integration_check.jl); for a rule proved over R
# the answer is also compared with the certified replacement up to a
# constant, and the note says "certified: agree" or "certified: differ".

isdefined(Main, :check_integral) || include(joinpath(@__DIR__, "..", "lib", "integration_check.jl"))

# candidate value sets; the first that satisfies the conditions is used
const CANDIDATES = [
    FPARAMS,
    Dict(:a => 2.0, :b => 3.0, :c => 5.0, :d => 7.0, :e => 1.0, :f => 2.0, :g => 3.0, :h => 5.0, :m => 2.0, :n => 3.0,
         :p => 2.0, :q => 3.0, :r => 2.0, :s => 3.0, :k => 2.0, :j => 1.0, :i => 2.0, :A => 2.0, :B => 3.0, :C => 5.0, :D => 1.0, :F => 2.0),
    Dict(:a => 2.0, :b => 3.0, :c => 5.0, :d => 7.0, :e => 1.0, :f => 2.0, :g => 3.0, :h => 5.0, :m => -2.0, :n => 2.0,
         :p => -3.0, :q => 1.0, :r => 2.0, :s => 3.0, :k => 2.0, :j => 1.0, :i => 2.0, :A => 2.0, :B => 3.0, :C => 5.0, :D => 1.0, :F => 2.0),
    Dict(:a => 1.7, :b => 0.6, :c => 2.3, :d => 1.1, :e => 0.7, :f => 1.3, :g => 0.9, :h => 1.9, :m => 2.0, :n => 2.0,
         :p => 0.5, :q => 1.5, :r => 2.1, :s => 1.9, :k => 2.0, :j => 0.35, :i => 0.65, :A => 1.4, :B => 0.9, :C => 2.2, :D => 0.5, :F => 1.6),
]

function read_rules()
    rows = NamedTuple[]
    for line in eachline(joinpath(@__DIR__, "rules.tsv"))
        (startswith(line, "#") || startswith(line, "id\t")) && continue
        f = split(line, '\t')
        length(f) == 9 || continue
        push!(rows, (id = String(f[1]), legacy = String(f[2]), real = String(f[3]), complex = String(f[4]),
                     variables = Symbol.(split(f[5])), integrand = String(f[6]), result = String(f[7]),
                     conditions = String(f[8]), description = String(f[9])))
    end
    rows
end

# evaluate the condition text with the parameters bound to the candidate values
function satisfies(conditions::String, vals::Dict{Symbol,Float64}, variables)
    conditions == "true" && return true
    ex = Meta.parse(conditions)
    bindings = Expr(:block, (Expr(:(=), v, get(vals, v, 1.0)) for v in variables if v != :x)...)
    try
        Core.eval(Main, Expr(:let, bindings, ex)) === true
    catch
        false
    end
end

function choose_values(rule)
    for cand in CANDIDATES
        satisfies(rule.conditions, cand, rule.variables) && return Dict{Symbol,Float64}(v => cand[v] for v in rule.variables if v != :x && haskey(cand, v))
    end
    nothing
end

const RULES = read_rules()
const PROBLEMS = NamedTuple[]
let skipped = 0
    for r in RULES
        vals = choose_values(r)
        if vals === nothing
            skipped += 1
            continue
        end
        params = merge(Dict{Symbol,Float64}(FPARAMS), vals)        # every parameter symbol has a value; the rule's own first
        certified = r.real == "proved" ? r.result : nothing
        push!(PROBLEMS, (name = r.id * " " * first(r.integrand, 70), op = :integrate_text,
                         args = V -> (r.integrand, "x", params),
                         check = o -> check_integral(o, r.integrand, ""; params = params, certified = certified),
                         note = "int " * first(r.integrand, 100) * " dx; R: " * r.real * ", C: " * r.complex * "; " *
                                join(["$k=$(v)" for (k, v) in sort!(collect(vals); by = kv -> string(kv[1]))], " ") *
                                "; " * r.legacy,
                         accept_unsolved = false))
    end
    @info "bench H: $(length(PROBLEMS)) rules with admissible values, $skipped without"
end
