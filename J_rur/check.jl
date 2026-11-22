# System-neutral RUR checker using rational polynomial arithmetic and BigFloat.
# Coefficient vectors are in ascending degree order.
using Random: MersenneTwister, rand
const RQ = Rational{BigInt}
trimq(p) = (q = copy(p); while length(q) > 1 && iszero(last(q)); pop!(q); end; q)
function addq(a, b)
    c = fill(zero(RQ), max(length(a), length(b)))
    for i in eachindex(a); c[i] += a[i]; end
    for i in eachindex(b); c[i] += b[i]; end
    trimq(c)
end
function mulq(a, b)
    c = fill(zero(RQ), length(a) + length(b) - 1)
    for i in eachindex(a), j in eachindex(b); c[i+j-1] += a[i]*b[j]; end
    trimq(c)
end
function powq(a, n)
    r = RQ[1]
    for _ in 1:n; r = mulq(r, a); end
    r
end
function divremq(a, b)
    b = trimq(b); iszero(last(b)) && error("zero divisor")
    r = trimq(a); q = fill(zero(RQ), max(1, length(r)-length(b)+1))
    while !(length(r) == 1 && iszero(r[1])) && length(r) >= length(b)
        k = length(r)-length(b); c = last(r)/last(b); q[k+1] += c
        for j in eachindex(b); r[k+j] -= c*b[j]; end
        r = trimq(r)
    end
    trimq(q), r
end
evalq(p, x) = foldr((a, v) -> a + x*v, p; init=zero(x))
function gcdisconstant(a,b)
    while !(length(b) == 1 && iszero(b[1])); _, r = divremq(a,b); a,b = b,r; end
    length(trimq(a)) == 1 && !iszero(a[1])
end

function check_rur(out, polys::Vector{String}, vars::Vector{String})
    required = (:vars, :linear_form, :elim, :denom, :param, :solutions)
    all(x -> hasproperty(out, x), required) || return (:unverified, "RUR format unavailable")
    out.vars == vars && isempty(out.linear_form) && length(out.param) in (length(vars)-1, length(vars)) ||
        return (:unverified, "unsupported variable order or separating linear form")
    parameter_index = hasproperty(out, :parameter_index) ? out.parameter_index : length(vars)
    1 <= parameter_index <= length(vars) || return (:unverified, "unsupported separating variable")
    elim, denom = trimq(RQ.(out.elim)), trimq(RQ.(out.denom))
    length(elim) > 1 || return (:unverified, "constant elimination polynomial")
    gcdisconstant(elim, denom) || return (:unverified, "lifting denominator vanishes at an elimination root")
    maps = [map(RQ, p) for p in out.param]
    length(maps) == length(vars)-1 && insert!(maps, parameter_index, mulq(RQ[0,1], denom))
    # Homogenise each input by a common power of the denominator, divide by
    # the elimination polynomial, and evaluate the resulting identity at
    # fixed independent rational points. The zero remainder checks all roots.
    rng = MersenneTwister(0x726f6f74)
    samples = [RQ(rand(rng, -100:100), rand(rng, 1:100)) for _ in 1:4]
    for s in polys
        f = Poly.parse_poly(s, vars)
        d = maximum(sum(m) for m in keys(f); init=0)
        numerator = RQ[0]
        for (m,c) in f
            term = RQ[c]
            for i in eachindex(vars); term = mulq(term, powq(maps[i], m[i])); end
            term = mulq(term, powq(denom, d-sum(m)))
            numerator = addq(numerator, term)
        end
        quotient, remainder = divremq(numerator, elim)
        all(iszero, remainder) || return (:wrong, "lifting map fails polynomial substitution")
        for t in samples
            evalq(numerator,t) == evalq(quotient,t)*evalq(elim,t) ||
                return (:wrong, "lifting identity failed at a test point")
        end
    end
    isempty(out.solutions) && return (:unverified, "no real solutions returned; complex roots are not isolated by this adapter")
    worst = BigFloat(0)
    setprecision(256) do
        for sol in out.solutions
            length(sol) == length(vars) || return (:wrong, "solution has the wrong dimension")
            x = BigFloat.(sol)
            for s in polys
                f = Poly.parse_poly(s, vars)
                terms = [BigFloat(c) * prod(x[i]^m[i] for i in eachindex(x)) for (m,c) in f]
                residual = abs(sum(terms; init=BigFloat(0)))
                scale = max(BigFloat(1), sum(abs, terms; init=BigFloat(0)))
                worst = max(worst, residual/scale)
                residual <= scale * big(2.0)^(-70) || return (:wrong, "real solution fails high-precision substitution")
            end
            t = x[parameter_index]; den = evalq(BigFloat.(denom), t)
            iszero(den) && return (:unverified, "zero lifting denominator")
            for i in eachindex(vars)
                lifted = evalq(BigFloat.(maps[i]),t)/den
                abs(lifted-x[i]) <= max(BigFloat(1),abs(x[i])) * big(2.0)^(-70) ||
                    return (:wrong, "reported solution does not match lifting map")
            end
        end
        (:verified_numeric, "$(length(out.solutions)) real solutions substituted at 256-bit precision; max scaled residual=$(worst); exact lifting identities; complex roots not isolated")
    end
end
