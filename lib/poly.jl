# Plain-Julia sparse multivariate polynomials for the checks of bench G.
#
# Every system returns its Gröbner basis as printed strings; this file parses
# them (the syntaxes of Giac, AbstractAlgebra/Nemo and SymPy: `^` or `**`,
# `//` or `/` for rationals, integer coefficients of a prime field printed as
# integers), puts a basis in canonical form (monic, degrevlex order, sorted) so
# that two reduced bases are equal iff their canonical strings are, and
# reduces polynomials modulo a basis over a prime field (the division
# algorithm), which gives the system-neutral membership check. No CAS is used.

module Poly

using SHA: sha1

export parse_poly, canonical_basis, basis_digest, reduce_mod, is_reduced, leading_monomial, degrevlex_lt

# ---------------------------------------------------------------------------
# representation: Dict{exponent vector => coefficient}; coefficients are
# Rational{BigInt} over Q or Int (0 .. p-1) over GF(p)
# ---------------------------------------------------------------------------
const Mono = Vector{Int}

# degrevlex: higher total degree first; ties broken by the smallest last
# exponent being larger (the standard degrevlex: a < b if deg a < deg b, or
# equal degrees and the last non-zero entry of a - b is positive)
function degrevlex_lt(a::Mono, b::Mono)
    da, db = sum(a), sum(b)
    da != db && return da < db
    for i in length(a):-1:1
        a[i] != b[i] && return a[i] > b[i]
    end
    false
end

leading_monomial(f::AbstractDict) = reduce((m1, m2) -> degrevlex_lt(m1, m2) ? m2 : m1, keys(f))

# ---------------------------------------------------------------------------
# parser
# ---------------------------------------------------------------------------
struct Tok
    kind::Symbol   # :num, :id, :op, :lp, :rp, :eof
    text::String
end

function tokenize(s::AbstractString)
    toks = Tok[]
    i = firstindex(s); n = lastindex(s)
    while i <= n
        c = s[i]
        if isspace(c)
            i = nextind(s, i)
        elseif isdigit(c)
            j = i
            while j <= n && isdigit(s[j]); j = nextind(s, j); end
            push!(toks, Tok(:num, s[i:prevind(s, j)])); i = j
        elseif isletter(c) || c == '_'
            j = i
            while j <= n && (isletter(s[j]) || isdigit(s[j]) || s[j] == '_'); j = nextind(s, j); end
            push!(toks, Tok(:id, s[i:prevind(s, j)])); i = j
        elseif c == '*' && i < n && s[nextind(s, i)] == '*'
            push!(toks, Tok(:op, "^")); i = nextind(s, nextind(s, i))
        elseif c == '/' && i < n && s[nextind(s, i)] == '/'
            push!(toks, Tok(:op, "/")); i = nextind(s, nextind(s, i))
        elseif c in ('+', '-', '*', '/', '^')
            push!(toks, Tok(:op, string(c))); i = nextind(s, i)
        elseif c == '('
            push!(toks, Tok(:lp, "(")); i = nextind(s, i)
        elseif c == ')'
            push!(toks, Tok(:rp, ")")); i = nextind(s, i)
        else
            error("unexpected character '$c' in polynomial")
        end
    end
    push!(toks, Tok(:eof, ""))
    toks
end

mutable struct Parser
    toks::Vector{Tok}
    pos::Int
    vars::Dict{String,Int}
    nv::Int
end
peek(p::Parser) = p.toks[p.pos]
advance!(p::Parser) = (p.pos += 1; p.toks[p.pos - 1])

const QPoly = Dict{Mono,Rational{BigInt}}
qconst(p::Parser, c) = QPoly(zeros(Int, p.nv) => Rational{BigInt}(c))

function padd(f::QPoly, g::QPoly, sign::Int)
    h = copy(f)
    for (m, c) in g
        v = get(h, m, Rational{BigInt}(0)) + sign * c
        v == 0 ? delete!(h, m) : (h[m] = v)
    end
    h
end
function pmul(f::QPoly, g::QPoly)
    h = QPoly()
    for (m1, c1) in f, (m2, c2) in g
        m = m1 .+ m2
        v = get(h, m, Rational{BigInt}(0)) + c1 * c2
        v == 0 ? delete!(h, m) : (h[m] = v)
    end
    h
end
isconst(f::QPoly) = all(m -> all(==(0), m), keys(f))
constval(f::QPoly) = isempty(f) ? Rational{BigInt}(0) : first(values(f))
function ppow(f::QPoly, e::Int)
    e == 0 && return QPoly(zeros(Int, length(first(keys(f)))) => Rational{BigInt}(1))
    r = f
    for _ in 2:e; r = pmul(r, f); end
    r
end

function parse_expr(p::Parser)
    f = parse_term(p)
    while peek(p).kind == :op && peek(p).text in ("+", "-")
        op = advance!(p).text
        f = padd(f, parse_term(p), op == "+" ? 1 : -1)
    end
    f
end
function parse_term(p::Parser)
    f = parse_factor(p)
    while peek(p).kind == :op && peek(p).text in ("*", "/")
        op = advance!(p).text
        g = parse_factor(p)
        if op == "*"
            f = pmul(f, g)
        else
            isconst(g) || error("division by a non-constant")
            f = QPoly(m => c / constval(g) for (m, c) in f)
        end
    end
    f
end
function parse_factor(p::Parser)
    t = peek(p)
    if t.kind == :op && t.text in ("+", "-")
        advance!(p)
        g = parse_factor(p)
        return t.text == "-" ? QPoly(m => -c for (m, c) in g) : g
    end
    b = parse_base(p)
    if peek(p).kind == :op && peek(p).text == "^"
        advance!(p)
        neg = false
        if peek(p).kind == :op && peek(p).text == "-"
            advance!(p); neg = true
        end
        e = advance!(p)
        e.kind == :num || error("exponent must be an integer")
        k = parse(Int, e.text)
        neg && error("negative exponent")
        return ppow(b, k)
    end
    b
end
function parse_base(p::Parser)
    t = advance!(p)
    if t.kind == :num
        return qconst(p, parse(BigInt, t.text))
    elseif t.kind == :id
        i = get(p.vars, t.text, 0)
        i == 0 && error("unknown symbol '$(t.text)'")
        m = zeros(Int, p.nv); m[i] = 1
        return QPoly(m => Rational{BigInt}(1))
    elseif t.kind == :lp
        f = parse_expr(p)
        advance!(p).kind == :rp || error("expected ')'")
        return f
    end
    error("unexpected token '$(t.text)'")
end

"""
    parse_poly(s, vars) -> Dict{Vector{Int},Rational{BigInt}}

Parse a printed polynomial in the variables `vars` (names, in order).
"""
function parse_poly(s::AbstractString, vars::Vector{String})
    p = Parser(tokenize(s), 1, Dict(v => i for (i, v) in enumerate(vars)), length(vars))
    f = parse_expr(p)
    peek(p).kind == :eof || error("trailing input '$(peek(p).text)'")
    filter!(kv -> kv[2] != 0, f)
    f
end

# ---------------------------------------------------------------------------
# prime field arithmetic (coefficients as Int in 0..p-1)
# ---------------------------------------------------------------------------
const FPoly = Dict{Mono,Int}

modp(c::Rational{BigInt}, p::Int) = (n = Int(mod(numerator(c), p)); d = Int(mod(denominator(c), p)); d == 0 && error("denominator divisible by p"); Int(mod(widemul(n, invmod(d, p)), p)))
function tofield(f::QPoly, p::Int)
    g = FPoly()
    for (m, c) in f
        v = modp(c, p)
        v != 0 && (g[m] = v)
    end
    g
end

# ---------------------------------------------------------------------------
# canonical form
# ---------------------------------------------------------------------------
function monic(f::QPoly)
    lm = leading_monomial(f); lc = f[lm]
    QPoly(m => c / lc for (m, c) in f)
end
function monic(f::FPoly, p::Int)
    lm = leading_monomial(f); inv = invmod(f[lm], p)
    FPoly(m => Int(mod(widemul(c, inv), p)) for (m, c) in f)
end

sorted_terms(f) = sort!(collect(f); lt = (a, b) -> degrevlex_lt(b[1], a[1]))   # leading term first
term_string(m, c) = string(c, "·", join(m, ","))
poly_string(f) = join((term_string(m, c) for (m, c) in sorted_terms(f)), " + ")

"""
    canonical_basis(strings, vars, p) -> (polys, canonical::Vector{String})

Parse the printed basis, make every polynomial monic (over Q if `p == 0`, over
GF(p) otherwise) and sort the basis by leading monomial. Two reduced Gröbner
bases of the same ideal in the same order give the same canonical strings.
"""
function canonical_basis(strings::AbstractVector{<:AbstractString}, vars::Vector{String}, p::Int)
    polys = Any[]
    for s in strings
        f = parse_poly(s, vars)
        isempty(f) && continue
        push!(polys, p == 0 ? monic(f) : monic(tofield(f, p), p))
    end
    sort!(polys; lt = (f, g) -> degrevlex_lt(leading_monomial(g), leading_monomial(f)))
    (polys, [poly_string(f) for f in polys])
end

basis_digest(canonical::Vector{String}) = bytes2hex(sha1(join(canonical, "\n")))[1:12]

# ---------------------------------------------------------------------------
# reducedness and reduction
# ---------------------------------------------------------------------------
divides(a::Mono, b::Mono) = all(i -> a[i] <= b[i], eachindex(a))

"""
    is_reduced(polys) -> Bool

True when no term of any polynomial is divisible by the leading monomial of
another one (and the basis is monic, which `canonical_basis` ensures).
"""
function is_reduced(polys)
    lms = [leading_monomial(f) for f in polys]
    for (i, f) in enumerate(polys), m in keys(f), (j, lm) in enumerate(lms)
        i != j && divides(lm, m) && return false
    end
    true
end

"""
    reduce_mod(f, basis, p; maxsteps) -> remainder (Dict), steps

Division algorithm over GF(p): repeatedly cancel the largest term of `f`
divisible by a leading monomial of `basis` (every element monic). `f` and the
basis are FPoly over the same prime. Stops after `maxsteps` cancellations.
"""
function reduce_mod(f::FPoly, basis::Vector{FPoly}, p::Int; maxsteps = 2_000_000)
    lms = [leading_monomial(g) for g in basis]
    r = copy(f)
    steps = 0
    # terms not reducible by any leading monomial are moved to `done`
    done = FPoly()
    while !isempty(r)
        m = leading_monomial(r)
        c = r[m]
        j = findfirst(lm -> divides(lm, m), lms)
        if j === nothing
            done[m] = c
            delete!(r, m)
            continue
        end
        steps += 1
        steps > maxsteps && return (merge(done, r), steps)
        q = m .- lms[j]
        for (mg, cg) in basis[j]
            mm = mg .+ q
            v = mod(get(r, mm, 0) - widemul(c, cg), p)
            v == 0 ? delete!(r, mm) : (r[mm] = Int(v))
        end
    end
    (done, steps)
end

end # module
