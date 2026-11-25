using Test
include(joinpath(@__DIR__, "..", "lib", "integration_systems.jl"))
@test selected_integration_systems("") == collect(INTEGRATION_SYSTEMS)
@test selected_integration_systems("sage_giac, sage_sympy") == ["sage_giac", "sage_sympy"]
@test_throws ErrorException selected_integration_systems("sage_giac,typo")
@test_throws ErrorException selected_integration_systems("sage_giac,sage_giac")
