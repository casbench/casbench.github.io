# Selection affects only which G system passes run, never their fixed inputs.
const G_DEFAULT_SYSTEMS = ("giac", "groebner", "msolve", "sympy", "sage_singular", "sage_giac", "macaulay2", "grobx")
function selected_g_systems(raw::AbstractString)
    isempty(strip(raw)) && return collect(G_DEFAULT_SYSTEMS)
    names = strip.(split(raw, ','))
    all(x -> x in G_DEFAULT_SYSTEMS, names) || error("unknown BENCH_G_SYSTEMS entry")
    length(unique(names)) == length(names) || error("duplicate BENCH_G_SYSTEMS entry")
    String.(names)
end
