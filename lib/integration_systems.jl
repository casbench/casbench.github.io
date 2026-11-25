# Selection only changes the systems run, never the integration problems.
const INTEGRATION_SYSTEMS = ("giac", "symbolics", "sympy", "symj", "maxima", "fricas", "sage_giac", "sage_maxima", "sage_fricas", "sage_sympy", "computeengine")
function selected_integration_systems(raw::AbstractString)
    isempty(strip(raw)) && return collect(INTEGRATION_SYSTEMS)
    names = strip.(split(raw, ','))
    all(x -> x in INTEGRATION_SYSTEMS, names) || error("unknown BENCH_INTEGRATION_SYSTEMS entry")
    length(unique(names)) == length(names) || error("duplicate BENCH_INTEGRATION_SYSTEMS entry")
    String.(names)
end
