# Machine-readable operation summaries. Timeouts and other failures remain in
# the attempted denominator; they are never substituted for measured times.
include(joinpath(@__DIR__, "lib", "metrics.jl"))
using .BenchMetrics: operation_metrics

let files = sort(filter(p -> endswith(p, ".tsv"), readdir(RESULTS; join=true)))
    # A hard-tier G pass writes separate files but contributes to the same
    # per-system operation profile when a base file exists.
    merged = Dict{String,Vector{Record}}()
    for p in files
        base = replace(p, "G_groebner_hard_" => "G_groebner_")
        target = base != p && isfile(base) ? base : p
        append!(get!(merged, target, Record[]), read_records(p))
    end
    data = [(path=p, rows=merged[p]) for p in sort(collect(keys(merged)))]
    # The supervisor leaves op blank on timeout/crash. Recover it from another
    # system's record for the same bench and case when it is unambiguous.
    ops = Dict{Tuple{String,Int},Set{String}}()
    for d in data, r in d.rows
        r.idx > 0 && !isempty(r.op) && push!(get!(ops, (r.bench, r.idx), Set{String}()), r.op)
    end
    open(joinpath(TABLES, "operation_metrics.tsv"), "w") do io
        println(io, "bench\tsource\top\tattempted\tsolved\ttimed\tfraction\tq1_s\tmedian_s\tq3_s")
        for d in data
            groups = Dict{Tuple{String,String},Vector{NamedTuple}}()
            for r in d.rows
                r.idx > 0 || continue
                candidates = get(ops, (r.bench, r.idx), Set{String}())
                op = isempty(r.op) && length(candidates) == 1 ? first(candidates) : r.op
                isempty(op) && (op = "[unknown operation]")
                row = (idx=r.idx, op=op, status=r.status, t_warm=r.t_warm, t_first=r.t_first)
                push!(get!(groups, (r.bench, op), NamedTuple[]), row)
            end
            for ((bench, op), rows) in sort(collect(groups); by=first)
                m = operation_metrics(rows)
                println(io, join((bench, basename(d.path), op, m.attempted, m.solved, m.timed,
                                  m.fraction, m.q1, m.median, m.q3), '\t'))
            end
        end
    end
end
