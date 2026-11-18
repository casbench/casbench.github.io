# Fixed inputs for bench C. Each entry is (label, integer as a string, expected
# number of distinct prime factors or 0 if not asserted).
#
# The semiprimes were produced once by generate_inputs.jl (nextprime of fixed
# starting points, no randomness) and pasted here so that the bench never
# draws inputs at run time. The 60-digit semiprime is the one used in the
# JuliaCon 2026 talk and in JuliaMath/Primes.jl issue 159.
const INPUTS = [
    # ordinary Int64 inputs (where Primes.jl is expected to be fastest)
    ("Int64 2^31-1 (prime)", "2147483647", 1),
    ("Int64 600851475143", "600851475143", 4),
    ("Int64 1234567890123456789", "1234567890123456789", 6),
    ("Int64 2^63-1", "9223372036854775807", 6),
    ("Int64 10^18+9 (prime)", "1000000000000000009", 1),
    # smooth integers (many small factors)
    ("smooth 2^40 3^20 5^10", "37439062426244874240000000000", 3),
    ("smooth 30# primorial", "31610054640417607788145206291543662493274686990", 30),
    ("smooth 20!^2", "5919012181389927685417441689600000000", 8),
    # semiprimes p*q with p and q of equal size
    ("semiprime 20 digits", "21000249622672311701", 2),   # 3000012373 * 7000054337
    ("semiprime 30 digits", "210000000024964400000672351479", 2),   # 300000000012371 * 700000000054349
    ("semiprime 40 digits", "2100000000000002494400000000000670898939", 2),   # 30000000000000012347 * 70000000000000054337
    ("semiprime 50 digits", "21000000000000000000249532000000000000000671787807", 2),   # 3000000000000000000012367 * 7000000000000000000054321
    ("semiprime 60 digits", "632459103267572196107100983820469021721602147490918660274601", 2),
]
