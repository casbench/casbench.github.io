using Serialization
request, response, ready, command = ARGS
write(command, "simplify(diff(x^2/2,x)-x)")
write(ready, "ready")
mode = get(ENV, "BENCH_FAKE_VERIFY_MODE", "pass")
mode == "timeout" && sleep(3)
mode == "crash" && exit(2)
status = mode == "pass" ? "verified_symbolic" : "verify_unsolved"
open(io -> serialize(io, (status=status, time=0.125)), response, "w")
