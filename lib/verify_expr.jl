# Exact-only Julia syntax for reconstructing an answer in the same symbolic
# system. Decimal literals are rejected rather than silently treated as exact.
# Constant divisions become rationals before Julia evaluates them.
function exact_verify_expr(source::AbstractString)
    ex = Mapleish.julia_expr(source)
    function constant_arithmetic(x)
        x isa Integer && return true
        x isa Expr && x.head == :call || return false
        x.args[1] in (:+, :-, :*, :/, ://, :^) && all(constant_arithmetic, x.args[2:end])
    end
    function visit(x)
        x isa AbstractFloat && error("inexact decimal in symbolic verification")
        (x isa Integer || x isa Symbol) && return x
        x isa Expr && x.head == :call || error("unsupported verification expression")
        op = x.args[1]
        op isa Symbol || error("unsupported verification operation")
        args = [visit(a) for a in x.args[2:end]]
        if op == :/ && length(args) == 2 && all(constant_arithmetic, args)
            op = ://
        end
        Expr(:call, op, args...)
    end
    visit(ex)
end
