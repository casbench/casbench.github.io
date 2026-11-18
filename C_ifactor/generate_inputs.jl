# Produce the semiprimes of inputs.jl deterministically and print the lines to
# paste there. Run once; the bench itself never calls this.
#
#   julia --project=envs/intfactor C_ifactor/generate_inputs.jl
using Primes

function semiprime(digits)
    h = digits ÷ 2
    p = nextprime(big(10)^(h - 1) * 3 + 12345)
    q = nextprime(big(10)^(h - 1) * 7 + 54321)
    @assert ndigits(p * q) == digits
    (p, q, p * q)
end

for d in (20, 30, 40, 50)
    p, q, n = semiprime(d)
    println("    (\"semiprime $d digits\", \"$n\", 2),   # $p * $q")
end
# checks on the fixed non-semiprime inputs
@assert big(2)^40 * big(3)^20 * big(5)^10 == parse(BigInt, "37439062426244874240000000000")
@assert prod(primes(113); init = big(1)) == parse(BigInt, "31610054640417607788145206291543662493274686990")
@assert factorial(big(20))^2 == parse(BigInt, "5919012181389927685417441689600000000")
println("fixed inputs verified")
