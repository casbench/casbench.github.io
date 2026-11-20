# History of the runs (included by make_tables.jl): one row per host, bench
# and system per run in results/history.tsv, from which the site draws its
# time series. A row is added when the current results of a (host, bench,
# system) carry a run date (the last block of results/<host>/machine.txt for
# that pair) that is not in the file yet; rows are never rewritten, so the
# file is the record.
#
# Columns: date, host, bench, system, n, verified, wrong, unverified, unsolved,
# unavailable, error, timeout, t_warm_sum, t_warm_median, versions, source

using Statistics: median

const HISTORY = joinpath(RESULTS_ROOT, "history.tsv")
const HISTORY_HEADER = "date\thost\tbench\tsystem\tn\tverified\twrong\tunverified\tunsolved\tunavailable\terror\ttimeout\tt_warm_sum\tt_warm_median\tversions\tsource"
const HISTORY_FIXED = ("host", "host_slug", "kernel", "cpu", "memory_GiB", "julia", "julia_threads", "bench", "system", "giac_version",
                       "run_id", "harness_commit", "harness_dirty", "giac_jl_commit", "osr_commit", "load_avg", "calibration_s")

# (bench, system key) -> (date, versions) from the last block of the host's machine.txt mentioning the pair
function run_dates(hostdir)
    out = Dict{Tuple{String,String},Tuple{String,String}}()
    path = joinpath(hostdir, "machine.txt")
    isfile(path) || return out
    date = ""; kv = Dict{String,String}()
    flush!() = begin
        if haskey(kv, "bench")
            vers = join(["$k $v" for (k, v) in kv if !(k in HISTORY_FIXED)], "; ")
            out[(kv["bench"], get(kv, "system", ""))] = (date, vers)   # bench A writes no system key
        end
        kv = Dict{String,String}()
    end
    for line in eachline(path)
        if startswith(line, "# ")
            flush!(); date = strip(line[3:end])
        elseif occursin('\t', line)
            k, v = split(line, '\t'; limit = 2); kv[k] = v
        end
    end
    flush!()
    out
end

function summary_row(date, host, bench, system, recs, versions, source)
    rs = [r for r in recs if r.case != "_load"]
    cnt(st) = count(r -> r.status == st, rs)
    tw = [r.t_warm for r in rs if r.status == "verified" && isfinite(r.t_warm)]
    join([date, host, bench, system, string(length(rs)), string(cnt("verified")), string(cnt("wrong")), string(cnt("unverified")),
          string(cnt("unsolved")), string(cnt("unavailable")), string(cnt("error")), string(cnt("timeout")),
          @sprintf("%.6g", sum(tw; init = 0.0)), isempty(tw) ? "NaN" : @sprintf("%.6g", median(tw)), versions, source], '\t')
end

hosts() = sort([h for h in readdir(RESULTS_ROOT) if isdir(joinpath(RESULTS_ROOT, h)) && isfile(joinpath(RESULTS_ROOT, h, "machine.txt"))])

function update_history()
    existing = isfile(HISTORY) ? readlines(HISTORY) : String[]
    isempty(existing) || startswith(existing[1], HISTORY_HEADER[1:9]) || error("results/history.tsv has the old header; add the host column")
    keys_seen = Set(Tuple(split(l, '\t')[1:4]) for l in existing[2:end] if count(==('\t'), l) >= 4)
    rows = String[]
    for host in hosts()
        hostdir = joinpath(RESULTS_ROOT, host)
        dates = run_dates(hostdir)
        for path in sort(filter(p -> endswith(p, ".tsv"), readdir(hostdir)))
            m = match(r"^([A-Z]_[a-z]+)_([a-z0-9_]+)\.tsv$", path)
            m === nothing && continue
            bench, system = m[1], m[2]
            recs = read_records(joinpath(hostdir, path))
            label = (i = findfirst(r -> r.case != "_load", recs); i === nothing ? "" : recs[i].system)
            d = get(dates, (bench, label), nothing)
            d === nothing && (d = get(dates, (bench, system), nothing))
            d === nothing && (d = get(dates, (bench, ""), nothing))
            d === nothing && continue
            date, vers = d
            (date, host, bench, system) in keys_seen && continue
            push!(rows, summary_row(date, host, bench, system, recs, vers, "run"))
        end
    end
    if isempty(existing)
        existing = [HISTORY_HEADER]
    end
    isempty(rows) || open(HISTORY, "w") do io
        for l in existing; println(io, l); end
        for l in rows; println(io, l); end
    end
    println("history: ", length(rows), " rows added")
end

update_history()
