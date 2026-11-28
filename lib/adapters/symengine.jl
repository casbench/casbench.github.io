# SymEngine.jl adapter: the C++ symengine core through its Julia wrapper. It
# has expansion, differentiation, substitution, series, numeric evaluation,
# code generation (lambdify) and matrices, no integration, no factorisation,
# no solving: most operations of benches B and D are `missing` here, which is
# the information those benches are about.
using SymEngine
using LinearAlgebra: det

const SYSTEM = "SymEngine.jl"
@vars x y z u v a b c s t k n d e f g h m p q r j i A B C D F
const VAR = Dict{Symbol,Any}(:x => x, :y => y, :z => z, :u => u, :v => v, :a => a, :b => b, :c => c, :s => s, :t => t,
                             :k => k, :n => n, :d => d, :e => e, :f => f, :g => g, :h => h, :m => m, :p => p, :q => q,
                             :r => r, :j => j, :i => i, :A => A, :B => B, :C => C, :D => D, :F => F)
VAR[:pi] = SymEngine.PI

isdefined(Main, :Mapleish) || include(joinpath(@__DIR__, "..", "mapleish.jl"))

# an expression from the Maple-like text (symengine's parser reads the Python-like dialect)
parse_text(s::String) = (t = Mapleish.translate(s, :sympy); log_input!(t); Basic(t))


struct CodegenAnswer
    values::Vector{Any}
    elapsed::Float64
    text::String
end
Base.string(c::CodegenAnswer) = c.text

@vars w
VAR[:w] = w
EXPAND_TEXT(s) = expand(parse_text(s))
EXPAND_DIFF_TEXT(s, v) = diff(expand(parse_text(s)), VAR[Symbol(v)])
SERIES_TEXT(s, v, x0, nn) = series(parse_text(s), VAR[Symbol(v)], x0, nn + 1)
SUBS_TEXT(s, rules) = subs(parse_text(s), Dict{Basic,Basic}(VAR[Symbol(l)] => parse_text(r) for (l, r) in rules))
EVAL_TEXT(s, pt) = N(subs(parse_text(s), Dict{Basic,Basic}(VAR[Symbol(k)] => Basic(v) for (k, v) in pt)))
function CODEGEN_TEXT(s, vars, points)
    f = lambdify(parse_text(s), [VAR[Symbol(v)] for v in vars])
    vals = Any[]; t0 = time_ns()
    for p in points; push!(vals, f(p...)); end
    CodegenAnswer(vals, (time_ns() - t0) / 1e9, "lambdify: $(length(vals)) calls")
end

const OPS = Dict{Symbol,Any}(
    :expand_text => EXPAND_TEXT, :expand_diff_text => EXPAND_DIFF_TEXT, :series_text => SERIES_TEXT,
    :subs_text => SUBS_TEXT, :eval_text => EVAL_TEXT, :codegen_text => CODEGEN_TEXT,
    :expand => f -> expand(f),
    :factor => missing,            # no polynomial factorisation
    :integrate => missing,         # no integration
    :simplify => missing,          # no simplifier beyond expand
    :solve => missing, :diophantine => missing, :desolve_ivp => missing, :laplace => missing, :ilaplace => missing,
    :partfrac => missing, :limit => missing, :sum => missing, :ifactor => missing, :assume_simplify => missing,
    :trigsimp => missing, :cfactor => missing, :gcd => missing, :resultant => missing, :discriminant => missing,
    :groebner => missing, :ztrans => missing, :eigenvals => missing,
    # bench D passes (f, x, order) and the rows of a matrix, as to every adapter (test/symengine_ops.jl; before
    # 2026-11-28 both raised a MethodError of the adapter)
    :series => (f, x, nn) -> series(f, x, 0, nn + 1),
    :det => M -> det(Basic[M[i][j] for i in eachindex(M), j in eachindex(M[1])]),
)

function EVAL(ex, vals)
    ex isa Number && !(ex isa Basic) && return ex
    ex isa Basic || return nothing
    d = Dict{Basic,Basic}(VAR[vv] => Basic(p) for (vv, p) in vals if haskey(VAR, vv))
    r = try
        N(subs(ex, d))
    catch
        return nothing
    end
    r isa Number && !(r isa Basic) ? r : nothing
end
NTERMS(ex) = ex isa Basic && SymEngine.get_symengine_class(ex) == :Add ? length(SymEngine.get_args(ex)) : 1
NFACTORS(ex) = ex isa Basic && SymEngine.get_symengine_class(ex) == :Mul ? length(SymEngine.get_args(ex)) : 1
IS_EXACT(ex) = occursin("pi", string(ex)) && !occursin(r"\d\.\d", string(ex))
UNSOLVED(op, out) = false
CLEARCACHE() = nothing
VERSIONS() = ["SymEngine" => string(pkgversion(SymEngine)), "symengine_jll" => string(pkgversion(SymEngine.SymEngine_jll))]
