# Run one integration self-check in its own process. The supervisor enforces
# a budget only after the adapter has loaded and this worker writes readiness.
# Request and response files are private, Julia-serialized NamedTuples.
using Serialization
include(joinpath(@__DIR__, "common.jl"))
using .BenchCommon
request_file, response_file, ready_file, command_file = ARGS
request = open(deserialize, request_file)
include(joinpath(@__DIR__, "adapters", request.system * ".jl"))
include(joinpath(@__DIR__, "verify_expr.jl"))

function save_response(result)
    tmp = response_file * ".tmp"
    open(io -> serialize(io, result), tmp, "w")
    mv(tmp, response_file; force=true)
end

op = get(OPS, :VERIFY_INTEGRAL, missing)
if op === missing || !isdefined(Main, :VERIFY_INTEGRAL_COMMAND)
    save_response((status="verify_unsolved", time=NaN))
    exit(0)
end
command = try
    VERIFY_INTEGRAL_COMMAND(request.answer, request.integrand, request.variable)
catch
    save_response((status="verify_unsolved", time=NaN))
    exit(0)
end
write(command_file, command)
write(ready_file, "ready")
t0 = time_ns()
result = try
    strip(string(op(request.answer, request.integrand, request.variable)))
catch
    ""
end
elapsed = (time_ns() - t0) / 1e9
status = result in ("0", "0/1", "0//1") ? "verified_symbolic" : "verify_unsolved"
save_response((status=status, time=elapsed))
