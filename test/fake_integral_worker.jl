using Serialization
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
bench, system, out, start, progress = ARGS[1:5]
parse(Int, start) > 1 && exit(0)
numeric_hang = get(ENV, "BENCH_FAKE_NUMERIC_HANG", "0") == "1"
numeric_hang || write(progress, "1\tcase")
r = Record(bench, system, 1, "case", "integrate_text", "verified_numeric", 1.25, 0.5, "x^2/2", "numeric", "integrate(x,x)")
if numeric_hang
    pending = Record(bench, system, 1, "case", "integrate_text", "unverified", 1.25, NaN, "x^2/2", "numeric verification interrupted", "integrate(x,x)")
    request = out * ".numeric-request"
    open(io -> serialize(io, (record=pending,)), request * ".tmp", "w")
    mv(request * ".tmp", request; force=true)
    get(ENV, "BENCH_FAKE_APPEND_BEFORE_HANG", "0") == "1" && append_record(out, r)
    # Announce progress only after the simulated checkpoint and optional row
    # are complete, so scheduler or compilation delays cannot race the test.
    phase = get(ENV, "BENCH_FAKE_BEFORE_NUMERIC", "0") == "1" ? "1\tcase" : "1\tcase\tnumeric"
    write(progress, phase)
    sleep(30)
end
if get(ENV, "BENCH_VERIFY_INTEGRALS", "0") == "1"
    request = out * ".verify-request"
    response = out * ".verify-response"
    open(io -> serialize(io, (system=system, answer="x^2/2", integrand="x", variable="x", record=r)), request, "w")
    write(progress, "1\tcase\tverify")
    if get(ENV, "BENCH_FAKE_WORKER_CRASH", "0") == "1"
        sleep(0.4)
        exit(2)
    end
    while !isfile(response); sleep(0.05); end
    v = open(deserialize, response)
    r = with_verification(r, v.status, v.time, v.command)
    append_record(out, r)
    rm(request; force=true)
    rm(response; force=true)
else
    append_record(out, r)
end
