# The integration paths corrected on 2026-11-26, against the real systems; needs the Nix toolchain (FriCAS, Sage,
# Giac), so it runs on the measuring machine, not in CI:
#   julia --project=envs/subprocess test/integration_paths.jl fricas|sage_fricas|sage_giac|sage_sympy
using Test
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using .BenchCommon
system = only(ARGS)
system in ("fricas", "sage_fricas", "sage_giac", "sage_sympy") || error("unknown adapter")
include(joinpath(@__DIR__, "..", "lib", "adapters", system * ".jl"))
include(joinpath(@__DIR__, "..", "lib", "integration_check.jl"))

@testset "integration paths: $system" begin
    if system in ("fricas", "sage_fricas")
        # bench F case 35: FriCAS returns two forms, for a^2 > b^2 and a^2 < b^2
        F = INTEGRATE_TEXT("1/(a+b*cos(x))", "x", FPARAMS)
        @test length(F.alternatives) == 2
        st, note = check_integral(F, "1/(a+b*cos(x))", "")
        @test st == :verified_numeric
        @test occursin("forms returned verifies", note) || occursin("of the 2 returned verifies", note)
    end
    if system == "fricas"
        # the parameter f: the integrand was bound to `f`, so `f = 1.3` substituted the integrand (no value, unverified)
        # and the symbolic check read the answer with f replaced (test/fricas_names.jl checks the names without FriCAS)
        G = INTEGRATE_TEXT("sin(f*x)", "x", FPARAMS)
        @test !isempty(G.values)
        @test check_integral(G, "sin(f*x)", "")[1] == :verified_numeric
        @test VERIFY_INTEGRAL("((-1)*cos(f*x))/f", "sin(f*x)", "x") == "0"
    end
    if system == "sage_giac"
        # bench H case 479: Giac's warning "Simplification assuming c near 0", reprinted at each evaluation of the
        # result, was recorded as the answer; it is now an error of the interface that says so
        params = merge(FPARAMS, Dict(:t => 0.75))
        A = try INTEGRATE_TEXT("(((s+(t*ln((i*((g+(h*x)))^(n)))))*ln((e*(((f*((a+(b*x)))^(p))*((c+(d*x)))^(q)))^(r))))*((j+(k*x)))^((-1)))", "x", params)
            catch err; sprint(showerror, err) end
        @test !startswith(string(A), "Simplification")
        # bench F case 140: Giac fails ("Degree mismatch", also with Giac.jl directly); the error is Giac's own now,
        # and the next case must not read the previous value of the result variable
        B = try INTEGRATE_TEXT("(a+c/x^2+b/x)^(1/2)", "x", FPARAMS) catch err; sprint(showerror, err) end
        @test occursin(r"giac gave no antiderivative|giac: .*Error:", string(B))     # Giac's own failure, as with Giac.jl
        @test !occursin("error occurred running a Giac command", string(B))
        C = INTEGRATE_TEXT("x^2", "x", FPARAMS)
        @test check_integral(C, "x^2", "")[1] == :verified_numeric
    end
    if system in ("sage_sympy", "sage_fricas", "sage_giac")
        # an exception is reported with its type and text: sage_error: NameError: name ... is not defined
        A = try INTEGRATE_TEXT("casbenchundefined(x)", "x", FPARAMS) catch err; sprint(showerror, err) end
        @test occursin(r"sage_error: NameError: .*casbenchundefined", string(A))
    end
    if system in ("sage_sympy",)
        # bench F case 616: Maple's Ei(2, b x) reaches Sage as exp_integral_e(2, b*x)
        A = try INTEGRATE_TEXT("Ei(2,b*x)/x", "x", FPARAMS) catch err; sprint(showerror, err) end
        @test !occursin("takes exactly", string(A))
    end
end
