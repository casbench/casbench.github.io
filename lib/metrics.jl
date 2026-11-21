# Summary statistics for a single operation, based on committed result records.
# Keep unsolved and censored observations in the denominator, never in timings.
module BenchMetrics

using Statistics: quantile

export operation_metrics

const SOLVED = ("verified", "verified_numeric", "verified_symbolic")

function operation_metrics(records)
    rows = filter(r -> r.idx > 0, records)
    operations = unique(r.op for r in rows)
    length(operations) <= 1 || throw(ArgumentError("summarise one operation at a time"))
    attempted = filter(r -> r.status != "unavailable", rows)
    solved = filter(r -> r.status in SOLVED, attempted)
    times = Float64[]
    for r in solved
        t = isfinite(r.t_warm) ? r.t_warm : r.t_first
        isfinite(t) && t >= 0 && push!(times, t)
    end
    n, nsolved = length(attempted), length(solved)
    # A missing time cannot stand in for a solved case in the distribution.
    enough = n > 0 && 2 * nsolved >= n && length(times) == nsolved
    q = enough ? quantile(times, [0.25, 0.5, 0.75]) : [NaN, NaN, NaN]
    (attempted = n, solved = nsolved, fraction = n == 0 ? NaN : nsolved / n,
     q1 = q[1], median = q[2], q3 = q[3], timed = length(times))
end

end
