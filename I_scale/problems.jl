# Bench I: throughput at scale. Where benches B and E time small expressions,
# this one asks how the time grows with the size of the expression, on fixed
# workloads: dense expansion of (x+y+z+w)^n, differentiation of a sum of 1326
# terms, a Taylor series of order 15, substitution and numeric evaluation on
# random trees of a thousand to a hundred thousand leaves, and code
# generation (a compiled function called a thousand times). Every answer is
# checked in plain Julia: the number of terms of an expansion, the value of
# the answer at a point (by the system's own numeric evaluation) against the
# value computed from the input.
#
# Operations the adapters map (text inputs in the Maple-like syntax):
#   :expand_text(expr)                        -> expression
#   :expand_diff_text(expr, var)              -> expression (expand, then differentiate)
#   :series_text(expr, var, x0, order)        -> expression (polynomial)
#   :subs_text(expr, [lhs => rhs, ...])       -> expression
#   :eval_text(expr, point::Dict{String,Float64}) -> number
#   :codegen_text(expr, vars, points)         -> (values::Vector, elapsed::Float64) of 1000 calls

using .BenchCommon: numeq
isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "lib", "mapleish.jl"))
include(joinpath(@__DIR__, "inputs.jl"))
using .ScaleInputs

const IPOINT = Dict(:x => 0.37, :y => 0.83, :z => 1.21, :w => 0.61, :a => 0.9, :b => 1.3, :c => 0.7)
ipoint_c() = Dict{String,ComplexF64}(string(k) => ComplexF64(v) for (k, v) in IPOINT)

binomial3(n) = binomial(n + 3, 3)

function check_expand(out, n)
    nt = NTERMS(out)
    nt == binomial3(n) || return (:wrong, "expected $(binomial3(n)) terms, got $nt")
    v = EVAL(out, Dict{Symbol,Float64}(IPOINT))
    v === nothing && return (:unverified, "not evaluable")
    ref = (IPOINT[:x] + IPOINT[:y] + IPOINT[:z] + IPOINT[:w])^n
    numeq(v, ref; rtol = 1e-8) ? (:verified, "terms=$nt") : (:wrong, "value $v, expected $ref")
end

function check_expand_diff(out)
    pt = Dict{Symbol,Float64}(:x => 1.1, :y => 0.7, :z => 1.3)
    f(x, y, z) = (x^y + y^z + z^x)^50
    h = 1e-6
    ref = (f(1.1 + h, 0.7, 1.3) - f(1.1 - h, 0.7, 1.3)) / (2h)
    v = EVAL(out, pt)
    v === nothing && return (:unverified, "not evaluable")
    numeq(v, ref; rtol = 1e-5) ? (:verified, "terms=$(NTERMS(out))") : (:wrong, "value $v, expected $ref")
end

function check_series(out)
    s = string(out)
    occursin(r"series\(|\bO\(", s) && return (:unsolved, "returned with an order term or unevaluated")
    v = EVAL(out, Dict{Symbol,Float64}(:x => 0.05))
    v === nothing && return (:unverified, "not evaluable")
    ref = sin(cos(1.05))
    abs(v - ref) <= 1e-12 ? (:verified, "terms=$(NTERMS(out))") : (:wrong, "value $v at x=0.05, expected $ref")
end

function check_subs(out, tree)
    pt = ipoint_c(); pt["a"] = 2 * sin(pt["b"])
    ref = tree_eval(tree, pt)
    v = EVAL(out, Dict{Symbol,Float64}(IPOINT))
    v === nothing && return (:unverified, "not evaluable")
    numeq(v, ref; rtol = 1e-8) ? (:verified, "nodes=$(tree_nodes(tree))") : (:wrong, "value $v, expected $ref")
end

function check_eval(out, tree)
    ref = tree_eval(tree, ipoint_c())
    (out isa Number && !(out isa Bool)) || return (:unverified, "not a number")
    numeq(ComplexF64(out), ref; rtol = 1e-8) ? (:verified, "nodes=$(tree_nodes(tree))") : (:wrong, "value $out, expected $ref")
end

const NCALLS = 1000
# the thousand points of the compiled-function calls: the point above, scaled
call_points() = [[IPOINT[:x] * (1 + 1e-4i), IPOINT[:y], IPOINT[:z], IPOINT[:a], IPOINT[:b], IPOINT[:c]] for i in 1:NCALLS]

function check_codegen(out, tree)
    hasfield(typeof(out), :values) || return (:unverified, "no values returned")
    vals = out.values
    length(vals) == NCALLS || return (:wrong, "$(length(vals)) values for $NCALLS calls")
    for i in (1, NCALLS ÷ 2, NCALLS)
        p = call_points()[i]
        pt = Dict{String,ComplexF64}("x" => p[1], "y" => p[2], "z" => p[3], "a" => p[4], "b" => p[5], "c" => p[6])
        numeq(ComplexF64(vals[i]), tree_eval(tree, pt); rtol = 1e-8) || return (:wrong, "call $i: $(vals[i]) expected $(tree_eval(tree, pt))")
    end
    (:verified, "nodes=$(tree_nodes(tree)) calls=$NCALLS")
end

const TREES = Dict{Tuple{Int,Int},ScaleInputs.Tree}()
tree_for(n, seed) = get!(TREES, (n, seed)) do
    random_tree(n, seed)
end

const PROBLEMS = NamedTuple[]
for w in WORKLOADS
    if w.kind == :expand
        push!(PROBLEMS, (name = w.name, op = :expand_text, args = V -> ("(x+y+z+w)^$(w.n)",), check = o -> check_expand(o, w.n),
                         note = "expand (x+y+z+w)^$(w.n): $(binomial3(w.n)) terms expected"))
    elseif w.kind == :expand_diff
        push!(PROBLEMS, (name = w.name, op = :expand_diff_text, args = V -> ("(x^y+y^z+z^x)^$(w.n)", "x"), check = check_expand_diff,
                         note = "expand (x^y+y^z+z^x)^50, then d/dx; checked at (1.1, 0.7, 1.3)"))
    elseif w.kind == :series
        push!(PROBLEMS, (name = w.name, op = :series_text, args = V -> ("sin(cos(1+x))", "x", 0, w.n), check = check_series,
                         note = "Taylor polynomial of order 15 at 0, checked at x = 0.05"))
    elseif w.kind == :subs
        tr_ = tree_for(w.n, w.seed)
        push!(PROBLEMS, (name = w.name, op = :subs_text, args = V -> (tree_text(tr_), ["a" => "2*sin(b)"]), check = o -> check_subs(o, tr_),
                         note = "random tree, $(tree_nodes(tr_)) nodes, seed $(w.seed); the rule touches every a"))
    elseif w.kind == :eval
        tr_ = tree_for(w.n, w.seed)
        push!(PROBLEMS, (name = w.name, op = :eval_text, args = V -> (tree_text(tr_), Dict(string(k) => v for (k, v) in IPOINT)), check = o -> check_eval(o, tr_),
                         note = "random tree, $(tree_nodes(tr_)) nodes, seed $(w.seed), numeric value at a point"))
    elseif w.kind == :codegen
        tr_ = tree_for(w.n, w.seed)
        push!(PROBLEMS, (name = w.name, op = :codegen_text, args = V -> (tree_text(tr_), ["x", "y", "z", "a", "b", "c"], call_points()),
                         check = o -> check_codegen(o, tr_),
                         note = "random tree, $(tree_nodes(tr_)) nodes, seed $(w.seed): compiled to a function, then $NCALLS calls (the warm time)"))
    end
end
