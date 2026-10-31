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

Strict Pareto dominance of resource `a` over `b`, exactly as specified in the
library documentation (`docs/main.dox`, DOMINANCE): `a` dominates `b` iff
`a[i] <= b[i]` for every component **and** `a[i] < b[i]` for at least one.
Consequently Pareto-equivalent labels (equal resources) are *not* dominated
and all of them stay extensible, as the NodeSolver/PathSolver specifications
require.

The compares are statically unrolled by StaticArrays (`all(a .<= b) &&
any(a .< b)`), keeping the hot path branch-light and allocation-free. Custom
resource types must implement
`dominates(a, b)`; problems may override the problem-level
`dominates(problem, a, b)` (the C++ `TestProblem` uses the weaker
`a <= b` componentwise relation, reproduced by its Julia port for parity).

# Contracts
- `@ensures result == (all(a .<= b) && any(a .< b))`
"""
@inline dominates(a::SVector{N,T}, b::SVector{N,T}) where {N,T<:Real} =
    all(a .<= b) && any(a .< b)
