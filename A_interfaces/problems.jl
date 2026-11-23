# Fixed paired expansion workloads for interface measurements. Each operation
# is a separate case, so the site never conflates interface paths by index.
using .BenchCommon: POINTS, numeq

const INTERFACE_INPUTS = [
    ("(x+y)^2", V -> (V[:x] + V[:y])^2, p -> (p[:x] + p[:y])^2),
    ("(x+2*y)^2", V -> (V[:x] + 2V[:y])^2, p -> (p[:x] + 2p[:y])^2),
    ("(x+y)^3", V -> (V[:x] + V[:y])^3, p -> (p[:x] + p[:y])^3),
    ("(x-y)^3", V -> (V[:x] - V[:y])^3, p -> (p[:x] - p[:y])^3),
]

function check_interface(out, ref)
    for p in POINTS
        v = EVAL(out, p)
        v === nothing && return :unverified
        numeq(v, ref(p)) || return :wrong
    end
    :verified_numeric
end

const PROBLEMS = let cases = NamedTuple[]
    for (mode, label) in ((:interface_object, "prebuilt object"), (:interface_text, "text"),
                          (:interface_session, "persistent process"), (:interface_cold, "new process"))
        for (input, build, ref) in INTERFACE_INPUTS
            args = mode == :interface_object ? (V -> (build(V),)) : (_ -> (input,))
            push!(cases, (name = "expand $input [$label]", op = mode, args = args,
                          check = out -> check_interface(out, ref),
                          note = "Numeric equality at three fixed points; expansion and interface work are both timed."))
        end
    end
    cases
end
