# Resource kernels. The C++ library lets each `Problem` define its own
# `Resource` struct; the Julia port keeps that freedom but ships a
# SIMD-friendly default: resources are `StaticArrays.SVector` whose FIRST
# component is the cost (mirrors `TestProblem::Resource{cost_, value_}` and the
# pybind11 `Resource{cost_, resources_[]}`).

"""
    resource_cost(r)

Cost component of resource `r`. Defaults to the first component for arrays and
to `r` itself for numbers. Port of `Resource::cost()`.
"""
@inline resource_cost(r::Number) = r
@inline resource_cost(r::AbstractArray) = r[1]

"""
    dominates(a, b) -> Bool

Weak componentwise dominance `a ≤ b` for `SVector` resources, port of the
canonical `Problem::dominates` (`a.cost() <= b.cost() && a.value() <= b.value()`
generalised to every component). The per-component compare is a register-SIMD
reduction (`@simd` over a statically sized vector).

Custom resource types must implement `dominates(a, b)`; problems may override
the problem-level `dominates(problem, a, b)`.
"""
@inline function dominates(a::SVector{N,T}, b::SVector{N,T}) where {N,T<:Real}
    ok = true
    @inbounds @simd for i in 1:N
        ok &= a[i] <= b[i]
    end
    return ok
end
