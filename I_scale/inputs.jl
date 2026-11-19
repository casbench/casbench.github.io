# Fixed inputs of bench I (throughput at scale). The small workloads are
# literal; the large expression trees are produced by a deterministic
# generator (a Park-Miller congruential generator, not Julia's RNG, whose
# stream may change between versions), so that every system receives the
# same tree and the check evaluates the same tree in plain Julia.
#
# A tree: nodes are atoms (the symbols x, y, z, a, b, c or small integers),
# unary applications (sin, cos) or binary applications (+, -, *). It is
# built by repeatedly pairing two random nodes under a random binary
# operation, or wrapping one under a unary function, until one node is left,
# which keeps the depth logarithmic in the size.

module ScaleInputs

export Tree, random_tree, tree_text, tree_eval, tree_nodes, WORKLOADS

mutable struct LCG; state::UInt64; end
next!(g::LCG) = (g.state = (g.state * 48271) % 2147483647; g.state)
rnd(g::LCG, n::Int) = Int(next!(g) % n) + 1

struct Tree
    op::Symbol                 # :atom, :sin, :cos, :+, :-, :*
    val::String                # the atom's text when op == :atom
    kids::Vector{Tree}
end

const ATOMS = ["x", "y", "z", "a", "b", "c", "1", "2", "3"]
const BINARY = [:+, :-, :*, :+, :-]      # * less often than + and -, to keep magnitudes moderate

"""random_tree(nleaves, seed) -> Tree with nleaves atoms (about 2 nleaves nodes)."""
function random_tree(nleaves::Int, seed::Int)
    g = LCG(UInt64(seed))
    nodes = Tree[Tree(:atom, ATOMS[rnd(g, length(ATOMS))], Tree[]) for _ in 1:nleaves]
    while length(nodes) > 1
        if rnd(g, 5) == 1                               # a unary function one time in five
            i = rnd(g, length(nodes))
            nodes[i] = Tree(rnd(g, 2) == 1 ? :sin : :cos, "", [nodes[i]])
        else
            i = rnd(g, length(nodes)); j = rnd(g, length(nodes) - 1); j >= i && (j += 1)
            op = BINARY[rnd(g, length(BINARY))]
            nodes[i] = Tree(op, "", [nodes[i], nodes[j]])
            deleteat!(nodes, j)
        end
    end
    nodes[1]
end

tree_nodes(t::Tree) = 1 + sum(tree_nodes, t.kids; init = 0)

"""The tree in the Maple-like syntax of the benches (fully parenthesised)."""
function tree_text(t::Tree)
    io = IOBuffer()
    _text(io, t)
    String(take!(io))
end
function _text(io, t::Tree)
    if t.op == :atom
        print(io, t.val)
    elseif t.op in (:sin, :cos)
        print(io, t.op, "("); _text(io, t.kids[1]); print(io, ")")
    else
        print(io, "("); _text(io, t.kids[1]); print(io, t.op); _text(io, t.kids[2]); print(io, ")")
    end
end

"""Numeric value of the tree at a point (atom name => value); complex arithmetic."""
function tree_eval(t::Tree, pt::Dict{String,ComplexF64})
    if t.op == :atom
        v = tryparse(Int, t.val)
        return v === nothing ? pt[t.val] : ComplexF64(v)
    elseif t.op == :sin
        return sin(tree_eval(t.kids[1], pt))
    elseif t.op == :cos
        return cos(tree_eval(t.kids[1], pt))
    end
    l, r = tree_eval(t.kids[1], pt), tree_eval(t.kids[2], pt)
    t.op == :+ ? l + r : t.op == :- ? l - r : l * r
end

# the workloads: (name, kind, parameters); the problem file turns them into cases
const WORKLOADS = [
    (name = "expand (x+y+z+w)^8", kind = :expand, n = 8),
    (name = "expand (x+y+z+w)^16", kind = :expand, n = 16),
    (name = "expand (x+y+z+w)^24", kind = :expand, n = 24),
    (name = "expand (x+y+z+w)^32", kind = :expand, n = 32),
    (name = "d/dx expand((x^y+y^z+z^x)^50)", kind = :expand_diff, n = 50),
    (name = "series sin(cos(1+x)), order 15", kind = :series, n = 15),
    (name = "substitute a -> 2 sin b, tree of 1000 leaves", kind = :subs, n = 1000, seed = 20261120),
    (name = "substitute a -> 2 sin b, tree of 10000 leaves", kind = :subs, n = 10000, seed = 20261120),
    (name = "substitute a -> 2 sin b, tree of 100000 leaves", kind = :subs, n = 100000, seed = 20261120),
    (name = "evaluate tree of 1000 leaves at a point", kind = :eval, n = 1000, seed = 20261120),
    (name = "evaluate tree of 10000 leaves at a point", kind = :eval, n = 10000, seed = 20261120),
    (name = "evaluate tree of 100000 leaves at a point", kind = :eval, n = 100000, seed = 20261120),
    (name = "compile tree of 1000 leaves, 1000 calls", kind = :codegen, n = 1000, seed = 20261120),
    (name = "compile tree of 10000 leaves, 1000 calls", kind = :codegen, n = 10000, seed = 20261120),
]

end # module
