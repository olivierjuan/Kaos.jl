# KaosJuLeanExt — formal verification extension (Sirocco.jl pattern).
#
# Loads only when JuLean.jl is in the environment (weak dependency): the
# production solver code in src/ stays completely untouched.
#
# Contents:
#   Tier 0 — DbC kernels wrapping the REAL Kaos kernels with @requires/@ensures
#            runtime contracts, hammered on random data by formal/verify_kernels.jl.
#   Tier 1 — the SMT/Lean theorem kernels live in kaos_formal_kernels.jl and
#            are registered into JuLean's SPEC_REGISTRY at __init__ (runtime
#            registry: precompilation would drop the side effect).

module KaosJuLeanExt

using Kaos
using StaticArrays
using JuLean

# ---- Tier 0: runtime DbC on the REAL Kaos kernels --------------------------

function dbc_dominates(a::SVector{N,T}, b::SVector{N,T}) where {N,T<:Real}
    result = Kaos.dominates(a, b)
    @ensures result == (all(a .<= b) && any(a .< b))
    return result
end

"Real `Kaos.add_path!` guarded by its data-structure invariants."
function dbc_add_path!(t::Kaos.PathTable, r, node::Integer, arc::Integer, parent::Integer)
    @requires 1 <= parent <= length(t.node)
    @requires 1 <= node
    @requires 1 <= arc
    i = Kaos.add_path!(t, r, node, arc, parent)
    @ensures i == length(t.node)
    @ensures t.parent[i] == parent && t.node[i] == node && t.arc[i] == arc
    @ensures t.resource[i] == r
    @ensures t.children[parent] >= 1
    return i
end

"Real `Kaos.update_incumbent!` guarded by the min-of-{previous, candidate} rule."
function dbc_update_incumbent!(t::Kaos.PathTable, i::Integer)
    @requires 1 <= i <= length(t.node)
    had = t.incumbent_index != 0
    prev = had ? t.incumbent_cost : nothing
    cand = Kaos.resource_cost(t.resource[i])
    is_new = Kaos.update_incumbent!(t, i)
    @ensures is_new == (!had || prev > cand)
    @ensures !had || t.incumbent_cost <= prev
    @ensures t.incumbent_cost <= cand
    @ensures !is_new || (t.incumbent_index == i)
    return is_new
end

"Real `Kaos.is_candidate` (BoundedFilter) guarded by the documented A* rule."
function dbc_is_candidate_bounded(cost::Real, bound::Real, incumbent::Real)::Bool
    @requires incumbent >= 0
    filter = Kaos.BoundedFilter([bound])
    result = Kaos.is_candidate(filter, nothing, SVector(cost, 0.0), 1, incumbent)
    @ensures result == (cost + bound < incumbent)
    return result
end

function __init__()
    # Tier 1 kernels are registered at load time: JuLean's SPEC_REGISTRY is a
    # runtime registry, and precompilation would drop module-level side
    # effects on other packages' state.
    include(joinpath(@__DIR__, "kaos_formal_kernels.jl"))
end

end # module
