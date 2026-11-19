# Draw the fixed sample of bench F from Nasser M. Abbasi's independent
# integration tests (12000.org, Summer 2024 edition), once:
#
#   julia --startup-file=no F_integration/sample.jl DIR_WITH_UNZIPPED_SYMPY_FORMAT [per_file]
#
# DIR is the unzipped CAS_integration_tests_2023_Sympy_format.zip (sha256
# 17db7974c344822ea7add21a72309758b6edbaf43f10263715e13a69465df6a6, from
# https://www.12000.org/my_notes/CAS_integration_tests/reports/summer_2024/input/).
# Every test file `<name>.txt` holds a Maple-like list `lst:=[[integrand, var,
# steps, antiderivative], ...]`, one entry per line; the entries are the Rubi
# test suite and the other collections, with the optimal antiderivative Rubi
# (or the collection) gives. `per_file` entries are drawn from each file with a
# fixed linear congruential generator (not Julia's RNG, whose stream may change
# between versions), so that the sample is the same forever.
#
# Output: F_integration/sample.tsv with the columns
#   id, file, line, integrand, var, steps, reference
# where `file` is the path inside the archive, `line` the 1-based line of the
# entry in that file, and `reference` the antiderivative the test file gives.
# The sample is committed; this script is kept for the record.

const PER_FILE = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 3
const SEED = UInt64(20261119)

# Park-Miller minimal standard generator, deterministic across Julia versions
mutable struct LCG; state::UInt64; end
function next!(g::LCG)
    g.state = (g.state * 48271) % 2147483647
    g.state
end
function sample_indices(g::LCG, n::Int, k::Int)
    k >= n && return collect(1:n)
    chosen = Int[]
    while length(chosen) < k
        i = Int(next!(g) % n) + 1
        i in chosen || push!(chosen, i)
    end
    sort!(chosen)
end

# split a line "[integrand,var,steps,antiderivative]," at the top-level commas
function fields(line::AbstractString)
    s = strip(line)
    endswith(s, ",") && (s = s[1:prevind(s, end)])
    (startswith(s, "[") && endswith(s, "]")) || return nothing
    s = s[nextind(s, 1):prevind(s, end)]
    out = String[]; depth = 0; start = 1
    for (i, c) in pairs(s)
        if c in ('(', '[', '{')
            depth += 1
        elseif c in (')', ']', '}')
            depth -= 1
        elseif c == ',' && depth == 0
            push!(out, strip(s[start:prevind(s, i)])); start = nextind(s, i)
        end
    end
    push!(out, strip(s[start:end]))
    length(out) == 4 ? out : nothing
end

function main()
    root = ARGS[1]
    files = String[]
    for (dir, _, fs) in walkdir(root), f in fs
        endswith(f, ".txt") && push!(files, joinpath(dir, f))
    end
    sort!(files)
    g = LCG(SEED)
    out = joinpath(@__DIR__, "sample.tsv")
    n = 0
    open(out, "w") do io
        println(io, "id\tfile\tline\tintegrand\tvar\tsteps\treference")
        for f in files
            entries = Tuple{Int,Vector{String}}[]
            for (ln, line) in enumerate(eachline(f))
                fl = fields(line)
                fl === nothing && continue
                any(x -> occursin('\t', x), fl) && continue
                push!(entries, (ln, fl))
            end
            isempty(entries) && continue
            rel = relpath(f, root)
            for i in sample_indices(g, length(entries), PER_FILE)
                ln, fl = entries[i]
                n += 1
                println(io, n, '\t', rel, '\t', ln, '\t', fl[1], '\t', fl[2], '\t', fl[3], '\t', fl[4])
            end
        end
    end
    println("$(length(files)) files, $n entries written to $out")
end

main()
