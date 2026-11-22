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

# Deterministic high-precision Aberth iteration. This is an independent
# numerical check, not a root-isolation or completeness certificate. If the
# roots cannot be separated or convergence is inadequate, the caller records
# unverified rather than attributing a failure to the answering system.
function complex_roots(elim; max_iterations=1000)
    p = trimq(RQ.(elim))
    n = length(p)-1
    1 <= n <= 96 || return nothing
    derivative = RQ[i*p[i+1] for i in 1:n]
    gcdisconstant(p, trimq(derivative)) || return nothing
    setprecision(256) do
        c = BigFloat.(p)
        # Fujiwara's bound avoids the excessive radius of the elementary
        # Cauchy bound for high-degree polynomials with large coefficients.
        radius = max(big(1), 2 * maximum(abs(c[i]/c[end])^(inv(BigFloat(n-i+1))) for i in 1:n))
        isfinite(radius) || return nothing
        roots = Complex{BigFloat}[]
        for k in 0:n-1
            angle = 2*big(pi)*(BigFloat(k)+big"0.375")/n
            push!(roots, radius * complex(cos(angle), sin(angle)))
        end
        target = big(2)^(-130)
        for _ in 1:max_iterations
            largest = BigFloat(0)
            for i in eachindex(roots)
                z = roots[i]
                value, deriv = Complex{BigFloat}(c[end]), Complex{BigFloat}(0)
                for j in n:-1:1
                    deriv = deriv*z + value
                    value = value*z + c[j]
                end
                iszero(deriv) && return nothing
                newton = value/deriv
                correction = Complex{BigFloat}(0)
                for j in eachindex(roots)
                    j == i && continue
                    delta = z-roots[j]
                    iszero(delta) && return nothing
                    correction += inv(delta)
                end
                divisor = 1-newton*correction
                iszero(divisor) && return nothing
                step = newton/divisor
                roots[i] = z-step
                isfinite(abs(roots[i])) || return nothing
                largest = max(largest, abs(step)/max(big(1),abs(roots[i])))
            end
            largest <= target && break
        end
        for (i,z) in enumerate(roots)
            bound = sum(abs(c[j])*abs(z)^(j-1) for j in eachindex(c); init=BigFloat(0))
            abs(evalq(c,z)) <= target * max(big(1),bound) || return nothing
            for j in 1:i-1
                abs(z-roots[j]) > big(2)^(-100)*max(big(1),abs(z),abs(roots[j])) || return nothing
            end
        end
        roots
    end
end

function check_rur(out, polys::Vector{String}, vars::Vector{String})
    required = (:vars, :linear_form, :elim, :denom, :param, :solutions)
    all(x -> hasproperty(out, x), required) || return (:unverified, "RUR format unavailable")
    n = length(vars)
    length(unique(out.vars)) == length(out.vars) || return (:unverified, "duplicate parametrization variables")
    positions = indexin(vars, out.vars)
    any(isnothing, positions) && return (:unverified, "parametrization omits an input variable")
    elim, denom = trimq(RQ.(out.elim)), trimq(RQ.(out.denom))
    length(elim) > 1 || return (:unverified, "constant elimination polynomial")
    length(elim) <= 97 || return (:unverified, "elimination degree exceeds the 96-root numeric verification limit")
    gcdisconstant(elim, denom) || return (:unverified, "lifting denominator vanishes at an elimination root")
    raw_maps = [map(RQ, p) for p in out.param]
    weights = fill(zero(RQ), n)
    if isempty(out.linear_form) && length(out.vars) == n
        parameter_index = hasproperty(out, :parameter_index) ? out.parameter_index :
                          findfirst(==(last(out.vars)), vars)
        parameter_index isa Integer && 1 <= parameter_index <= n || return (:unverified, "unsupported separating variable")
        if length(raw_maps) == n-1
            parameter_raw_index = findfirst(==(vars[parameter_index]), out.vars)
            insert!(raw_maps, parameter_raw_index, mulq(RQ[0,1], denom))
        end
        length(raw_maps) == n || return (:unverified, "unsupported lifting map")
        weights[parameter_index] = one(RQ)
    elseif length(out.vars) == n+1 && length(out.linear_form) == n+1 && length(raw_maps) == n
        all(i -> i !== nothing && i <= n, positions) || return (:unverified, "unsupported auxiliary-variable position")
        coefficients = try RQ[parse(BigInt, string(c)) for c in out.linear_form] catch; return (:unverified, "unsupported separating form") end
        iszero(last(coefficients)) && return (:unverified, "zero separating coefficient")
        # Different RUR conventions may store either sign. Select it by an
        # exact identity modulo the elimination polynomial, not by guessing.
        base = RQ[coefficients[positions[i]] / last(coefficients) for i in 1:n]
        ordered = [raw_maps[positions[i]] for i in 1:n]
        function valid_sign(sign)
            lhs = RQ[0]
            for i in 1:n
                lhs = addq(lhs, mulq(RQ[sign*base[i]], ordered[i]))
            end
            lhs = addq(lhs, mulq(RQ[0,-1], denom))
            _, remainder = divremq(lhs, elim)
            all(iszero, remainder)
        end
        if valid_sign(1)
            weights = base
        elseif valid_sign(-1)
            weights = -base
        else
            return (:unverified, "separating linear form does not match the lifting map")
        end
    else
        return (:unverified, "unsupported variable order or separating linear form")
    end
    maps = [raw_maps[positions[i]] for i in 1:n]
    separating(x) = sum(BigFloat(weights[i]) * x[i] for i in eachindex(x); init=BigFloat(0))
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
    roots = complex_roots(elim)
    roots === nothing && return (:unverified, "could not independently approximate and separate all complex roots")
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
            t = separating(x); den = evalq(BigFloat.(denom), t)
            iszero(den) && return (:unverified, "zero lifting denominator")
            for i in eachindex(vars)
                lifted = evalq(BigFloat.(maps[i]),t)/den
                abs(lifted-x[i]) <= max(BigFloat(1),abs(x[i])) * big(2.0)^(-70) ||
                    return (:wrong, "reported solution does not match lifting map")
            end
        end
        # A near-real root is treated conservatively. A mismatch is unverified,
        # since numerical root classification is not a proof of completeness.
        real_roots = filter(z -> abs(imag(z)) <= big(2)^(-70) * max(big(1), abs(real(z))), roots)
        length(real_roots) == length(out.solutions) ||
            return (:unverified, "reported real solution count differs from the independently approximated roots")
        matched = Set{Int}()
        for sol in out.solutions
            length(sol) == length(vars) || return (:wrong, "solution has the wrong dimension")
            t = separating(BigFloat.(sol))
            candidates = [i for i in eachindex(real_roots) if !(i in matched) &&
                          abs(real(real_roots[i])-t) <= big(2)^(-50)*max(big(1),abs(t))]
            isempty(candidates) && return (:unverified, "reported real solution does not match a separated numerical root")
            push!(matched, first(candidates))
        end
        # Approximate every complex root of the elimination polynomial, lift
        # it through the returned RUR, and substitute into each input.
        complex_worst = BigFloat(0)
        for t in roots
            den = evalq(BigFloat.(denom), t)
            iszero(den) && return (:unverified, "zero denominator at a computed complex root")
            x = [evalq(BigFloat.(map), t)/den for map in maps]
            for s in polys
                f = Poly.parse_poly(s, vars)
                terms = [BigFloat(c) * prod(x[i]^m[i] for i in eachindex(x)) for (m,c) in f]
                residual = abs(sum(terms; init=Complex{BigFloat}(0)))
                scale = max(BigFloat(1), sum(abs, terms; init=BigFloat(0)))
                complex_worst = max(complex_worst, residual/scale)
                residual <= scale * big(2)^(-70) || return (:unverified, "complex root lift did not pass high-precision substitution; numerical root conditioning may be responsible")
            end
        end
        (:verified_numeric, "$(length(out.solutions)) reported real solutions and $(length(roots)) independently approximated complex roots substituted at 256-bit precision; max scaled residuals=$(worst),$(complex_worst); exact lifting identities; complex root approximation is not a completeness certificate")
    end
end
