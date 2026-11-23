# Interface paths for existing adapters, or a supervised external process.
if SYSTEM_KEY in ("maxima", "fricas")
    include(joinpath(@__DIR__, "process_adapter.jl"))
else
    include(joinpath(@__DIR__, "..", "lib", "adapters", SYSTEM_KEY * ".jl"))
    if get(OPS, :expand, missing) !== missing
        let op = OPS[:expand]
            OPS[:interface_object] = expr -> begin
                isempty(INPUT_LOG) && log_input!("expand(" * string(expr) * ")")
                op(expr)
            end
        end
    end
    if get(OPS, :expand_text, missing) !== missing
        let op = OPS[:expand_text]
            OPS[:interface_text] = text -> begin
                isempty(INPUT_LOG) && log_input!("expand(" * text * ")")
                op(text)
            end
        end
    end
end
