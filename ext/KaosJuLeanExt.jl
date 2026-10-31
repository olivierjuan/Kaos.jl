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

const KERNEL_TACTICS = Dict{Symbol, String}(
    :kaos_incumbent_rule => "cases has_inc <;> simp [kaos_incumbent_rule] <;> by_cases h : prev > cand <;> simp [h] <;> linarith",
    :kaos_dominance_asymmetry2 => "",
    :kaos_dominance_transitivity2 => "",
    :kaos_dominance_additive_extension2 => "",
    :kaos_mincost_monotone => "",
    :kaos_incumbent_adopt => "",
    :kaos_incumbent_improve => "",
    :kaos_incumbent_hold => "",
)

const FORMAL_THEOREMS = [
    :kaos_dominance_asymmetry2,
    :kaos_dominance_transitivity2,
    :kaos_dominance_additive_extension2,
    :kaos_incumbent_rule,
    :kaos_mincost_monotone,
    :kaos_incumbent_adopt,
    :kaos_incumbent_improve,
    :kaos_incumbent_hold,
    :kaos_extend_batch_arr,
    :kaos_front_scan_arr,
]

"""
    Kaos.verify_formal_specifications(; backend=:Z3, timeout=30.0) -> Dict{Symbol, JuLean.VerificationResult}

Runs formal verification on Kaos decision-rule specifications and kernels.
- `backend=:Z3`: SMT falsification of declared contracts.
- `backend=:Lean4`: mechanized Lean 4 proof of declared contracts, zero sorry.
- `backend=:BMC`: bounded model checking on loop and array mutations.
"""
function Kaos.verify_formal_specifications(; backend::Symbol=:Z3, timeout::Float64=30.0)
    results = Dict{Symbol, JuLean.VerificationResult}()
    specs_to_verify = if backend == :BMC
        [:kaos_extend_batch_arr, :kaos_front_scan_arr]
    elseif backend == :Z3
        [:kaos_dominance_asymmetry2, :kaos_dominance_transitivity2, :kaos_dominance_additive_extension2, :kaos_incumbent_rule, :kaos_mincost_monotone]
    elseif backend == :Lean4
        [:kaos_dominance_asymmetry2, :kaos_dominance_transitivity2, :kaos_dominance_additive_extension2, :kaos_mincost_monotone, :kaos_incumbent_adopt, :kaos_incumbent_improve, :kaos_incumbent_hold, :kaos_incumbent_rule]
    else
        FORMAL_THEOREMS
    end

    for s in specs_to_verify
        tac = get(KERNEL_TACTICS, s, "")
        results[s] = if backend == :BMC
            JuLean.verify(s; backend=:BMC, depth=4, timeout=timeout)
        else
            JuLean.verify(s; backend=backend, timeout=timeout, tactic=tac)
        end
    end
    return results
end

"""
    Kaos.export_lean_specifications(filepath::String)

Exports all formalized Kaos kernel specifications into a standalone Lean 4 file.
"""
function Kaos.export_lean_specifications(filepath::String)
    return JuLean.export_lean_file(filepath; fns=FORMAL_THEOREMS, tactics=KERNEL_TACTICS)
end

function __init__()
    # 1. Formalize real Kaos kernels from docstrings
    for f in KERNEL_FUNCTIONS
        JuLean.formalize!(f)
    end

    # 2. Register Tier 1 & Tier 2 formal theorem kernels
    include(joinpath(@__DIR__, "kaos_formal_kernels.jl"))
end

end # module
