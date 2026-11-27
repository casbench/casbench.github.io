# The polynomial systems of benches G and J, from their definitions in the literature, written for this repository.
#
#   julia --startup-file=no tools/groebner/systems.jl          # writes G_groebner/inputs.jl and G_groebner/hard_inputs.jl
#
# A polynomial is a Dict from exponent vectors to rational coefficients, printed with its terms in decreasing
# degree-reverse-lexicographic order (the variables in the order given), coefficients as a//b, so that every system of
# the benches parses the same text. test/groebner_systems.jl checks that the committed files are what this script writes.

const Poly = Dict{Vector{Int},Rational{BigInt}}

mono(nv, idx...) = (e = zeros(Int, nv); for i in idx; e[i] += 1; end; e)
add!(p::Poly, e, c) = (p[e] = get(p, e, 0) + c; iszero(p[e]) && delete!(p, e); p)

# degrevlex: higher total degree first; then the one with the smaller exponent in the last differing variable
function degrevlex_greater(a, b)
    sum(a) != sum(b) && return sum(a) > sum(b)
    for i in length(a):-1:1
        a[i] != b[i] && return a[i] < b[i]
    end
    false
end
function monomial_text(e, vars)
    parts = String[]
    for (i, k) in enumerate(e)
        k == 0 && continue
        push!(parts, k == 1 ? vars[i] : "$(vars[i])^$k")
    end
    join(parts, "*")
end
coeff_text(c) = denominator(c) == 1 ? string(numerator(c)) : "$(numerator(c))//$(denominator(c))"
function poly_text(p::Poly, vars)
    terms = sort!(collect(p); lt = (x, y) -> degrevlex_greater(x[1], y[1]))
    out = IOBuffer()
    for (k, (e, c)) in enumerate(terms)
        m = monomial_text(e, vars)
        a = abs(c)
        body = isempty(m) ? coeff_text(a) : (a == 1 ? m : coeff_text(a) * "*" * m)
        print(out, k == 1 ? (c < 0 ? "-" : "") : (c < 0 ? " - " : " + "), body)
    end
    String(take!(out))
end

# Katsura n: unknowns x0..xn; for m = 0..n-1, sum over l in -n..n of x_|l| x_|m-l| (x_i = 0 beyond n) equals x_m,
# and x0 + 2 (x1 + ... + xn) = 1
function katsura(n)
    vars = ["x$i" for i in 0:n]; nv = n + 1
    polys = Poly[]
    for m in 0:n-1
        p = Poly()
        for l in -n:n
            i, j = abs(l), abs(m - l)
            j <= n && add!(p, mono(nv, i + 1, j + 1), 1)
        end
        push!(polys, add!(p, mono(nv, m + 1), -1))
    end
    p = add!(Poly(), mono(nv, 1), 1)
    for i in 1:n
        add!(p, mono(nv, i + 1), 2)
    end
    push!(polys, add!(p, mono(nv), -1))
    vars, polys
end

# cyclic n: for k = 1..n-1, the sum of the n cyclic products of k consecutive unknowns is 0; their product is 1
function cyclic(n)
    vars = ["z$i" for i in 1:n]
    polys = Poly[]
    for k in 1:n-1
        p = Poly()
        for i in 1:n
            add!(p, mono(n, (mod1(i + j, n) for j in 0:k-1)...), 1)
        end
        push!(polys, p)
    end
    push!(polys, add!(add!(Poly(), mono(n, 1:n...), 1), mono(n), -1))
    vars, polys
end

# eco n (Morgan): unknowns y1..yn; for k = 1..n-1, (y_k + sum_{i=1}^{n-k-1} y_i y_{i+k}) y_n = k, and
# y1 + ... + y_{n-1} + 1 = 0; the unknowns are named from `first` (x1.. for eco7, x0.. for the larger ones)
function eco(n; first = 1)
    vars = ["x$(i - 1 + first)" for i in 1:n]
    polys = Poly[]
    for k in 1:n-1
        p = add!(Poly(), mono(n, k, n), 1)
        for i in 1:n-k-1
            add!(p, mono(n, i, i + k, n), 1)
        end
        push!(polys, add!(p, mono(n), -k))
    end
    p = add!(Poly(), mono(n), 1)
    for i in 1:n-1
        add!(p, mono(n, i), 1)
    end
    push!(polys, p)
    vars, polys
end

# noon n (Noonburg's neural network): x_i (sum_{j != i} x_j^2) - 11/10 x_i + 1 = 0, scaled by 10
function noon(n)
    vars = ["x$i" for i in 1:n]
    polys = Poly[]
    for i in 1:n
        p = Poly()
        for j in 1:n
            j == i && continue
            add!(p, mono(n, i, j, j), 10)
        end
        add!(p, mono(n, i), -11)
        push!(polys, add!(p, mono(n), 10))
    end
    vars, polys
end

# Henrion's fifth system (the Henrion 5 problem of the polynomial system collections): its constants are the
# problem's own
function henrion5()
    vars = ["f1", "f2", "f3", "f4", "f5", "t"]; nv = 6
    T(c, idx...) = (mono(nv, idx...), Rational{BigInt}(c))
    rows = [
        [T(2, 1, 2, 3, 4, 5), T(-9823275)],
        [T(5, 1, 2, 3, 4), T(24//5, 1, 2, 3, 5), T(21//5, 1, 2, 4, 5), T(16//5, 1, 3, 4, 5), T(9//5, 2, 3, 4, 5), T(-4465125)],
        [T(4, 1, 2, 3), T(6, 1, 2, 4), T(6, 1, 3, 4), T(4, 2, 3, 4), T(18//5, 1, 2, 5), T(24//5, 1, 3, 5), T(18//5, 2, 3, 5),
         T(14//5, 1, 4, 5), T(14//5, 2, 4, 5), T(8//5, 3, 4, 5), T(-441486)],
        [T(3, 1, 2), T(4, 1, 3), T(3, 2, 3), T(4, 1, 4), T(4, 2, 4), T(3, 3, 4), T(12//5, 1, 5), T(12//5, 2, 5), T(12//5, 3, 5),
         T(7//5, 4, 5), T(-15498)],
        [T(2, 1), T(2, 2), T(2, 3), T(2, 4), T(6//5, 5), T(-215)],
        [T(1, 1), T(2, 2), T(3, 3), T(4, 4), T(5, 5), T(6, 6)],
    ]
    vars, [foldl((p, (e, c)) -> add!(p, e, c), r; init = Poly()) for r in rows]
end

# Chandrasekhar's H-equation discretised on n points: (2n - c) H_i - c sum_{j=1}^{n-1} i/(i+j) H_i H_j - 2n = 0, with
# c = 0.51234, the value of the classical system, taken as the exact rational of its binary64 representation (which is how
# the system has been distributed, hence its dyadic coefficients)
function chandra(n; c = Rational{BigInt}(0.51234))
    vars = ["H$i" for i in 1:n]
    polys = Poly[]
    for i in 1:n
        p = Poly()
        for j in 1:n-1
            add!(p, mono(n, i, j), -c * i // (i + j))
        end
        add!(p, mono(n, i), 2n - c)
        push!(polys, add!(p, mono(n), -2n))
    end
    vars, polys
end

const BASE = [("katsura5", katsura(5)), ("katsura6", katsura(6)), ("katsura7", katsura(7)), ("katsura8", katsura(8)),
              ("katsura9", katsura(9)), ("cyclic4", cyclic(4)), ("cyclic5", cyclic(5)), ("cyclic6", cyclic(6)),
              ("cyclic7", cyclic(7)), ("eco7", eco(7)), ("eco10", eco(10; first = 0)), ("noon4", noon(4)), ("noon5", noon(5)),
              ("noon6", noon(6)), ("henrion5", henrion5()), ("chandran5", chandra(5))]
const HARD = [("cyclic8", cyclic(8), 600), ("cyclic9", cyclic(9), 3600), ("katsura10", katsura(10), 600),
              ("eco11", eco(11; first = 0), 600), ("eco12", eco(12; first = 0), 600)]

function write_systems(io, name, (vars, polys), budget = nothing)
    print(io, "    (name = ", repr(name), ", vars = ", repr(vars), budget === nothing ? "," : ", budget = $budget, polys = [", "\n")
    budget === nothing && println(io, "     polys = [")
    for p in polys
        println(io, "        ", repr(poly_text(p, vars)), ",")
    end
    println(io, budget === nothing ? "     ])," : "    ]),")
end
function inputs_text()
    io = IOBuffer()
    println(io, "# The classical polynomial systems of benches G and J (Katsura, cyclic-n, eco, noon, Henrion, Chandrasekhar),")
    println(io, "# written by tools/groebner/systems.jl from their definitions and stored as plain strings, so that every system")
    println(io, "# parses the same input. Do not edit: regenerate with that script (test/groebner_systems.jl checks the file).")
    println(io, "const SYSTEMS = [")
    for (name, sys) in BASE
        write_systems(io, name, sys)
    end
    println(io, "]")
    String(take!(io))
end
function hard_inputs_text()
    io = IOBuffer()
    println(io, "# The hard tier of bench G, written by tools/groebner/systems.jl from the definitions of the systems.")
    println(io, "const HARD_SYSTEMS = [")
    for (name, sys, budget) in HARD
        write_systems(io, name, sys, budget)
    end
    println(io, "]")
    String(take!(io))
end

if abspath(PROGRAM_FILE) == @__FILE__
    root = joinpath(@__DIR__, "..", "..")
    write(joinpath(root, "G_groebner", "inputs.jl"), inputs_text())
    write(joinpath(root, "G_groebner", "hard_inputs.jl"), hard_inputs_text())
end
