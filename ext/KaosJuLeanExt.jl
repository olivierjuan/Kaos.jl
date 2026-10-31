# KaosJuLeanExt — formal verification extension (Sirocco.jl pattern).
#
# Loads only when JuLean.jl is in the environment (weak dependency): the
# production solver code in src/ stays completely untouched.
#
# Contents:
#   Tier 0 — Contracts live in Markdown docstrings of the REAL Kaos kernels;
#            JuLean.contracted(...) wraps them dynamically for runtime checking.
#   Tier 1 — the SMT/Lean theorem kernels live in kaos_formal_kernels.jl and
#            are registered into JuLean's SPEC_REGISTRY at __init__.

module KaosJuLeanExt

using Kaos
using StaticArrays
using JuLean

const KERNEL_FUNCTIONS = [
    Kaos.dominates,
    Kaos.add_path!,
    Kaos.update_incumbent!,
    Kaos.is_candidate,
    Kaos.is_feasible,
    Kaos.front_dominates,
    Kaos.add_dominant!,
    Kaos._extend_batch!,
    Kaos.solve,
]

const KERNEL_NAMES = [nameof(f) for f in KERNEL_FUNCTIONS]

# Dynamic contracted wrapper helper for runtime checking (from docstrings)
contracted(f::Function) = JuLean.contracted(f)

function __init__()
    # 1. Formalize real Kaos kernels from docstrings
    for f in KERNEL_FUNCTIONS
        JuLean.formalize!(f)
    end

    # 2. Register Tier 1 & Tier 2 formal theorem kernels
    include(joinpath(@__DIR__, "kaos_formal_kernels.jl"))
end

end # module
