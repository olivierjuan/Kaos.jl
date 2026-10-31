# Ports of EDF OSAK `algorithms/pareto_fronts/ParetoFrontValid.hxx` (node
# solver) and `ParetoFrontNew.hxx` (path solver).
#
# Deviation from the C++ headers: both fronts keep a contiguous `resource`
# array parallel to the index array so the dominance scan reads packed
# `SVector`s (SIMD) instead of chasing `pathTable[index].resource`.

"""
    ExtensibleFront{R}()

Per-node Pareto front of efficient labels that still deserve extension; port of
`rcspp::ParetoFrontValid`. Iteration is *consuming*: an entry is yielded at
most once, exactly when it is still flagged extensible.

Intentional fix over the C++ original: its `begin()` did not skip a consumed
first entry, so re-popping a node re-extended an already-extended label —
wasted work that weak dominance filtered afterwards anyway.
"""
mutable struct ExtensibleFront{R}
    index::Vector{Int}
    extendable::Vector{Bool}
    resource::Vector{R}
end
ExtensibleFront{R}() where {R} = ExtensibleFront{R}(Int[], Bool[], R[])

@inline function _push_entry!(f::ExtensibleFront{R}, i::Integer, r::R) where {R}
    push!(f.index, i)
    push!(f.extendable, true)
    push!(f.resource, r)
    return f
end

"""
    add_dominant!(p, f::ExtensibleFront, i, r) -> f

Drop the entries dominated by candidate `r` (order preserving, port of
`add_dominant_path`) then append label `i` flagged extensible.

# Contracts
- `@requires 1 <= i`
- `@ensures any(k -> f.index[k] == i, eachindex(f.index))`
- `@ensures !any(k -> dominates(p, r, f.resource[k]), eachindex(f.resource))`
"""
function add_dominant!(p, f::ExtensibleFront{R}, i::Integer, r::R) where {R}
    idx = f.index
    ext = f.extendable
    res = f.resource
    w = 0
    @inbounds for k in eachindex(idx)
        if !dominates(p, r, res[k])
            w += 1
            idx[w] = idx[k]
            ext[w] = ext[k]
            res[w] = res[k]
        end
    end
    resize!(idx, w)
    resize!(ext, w)
    resize!(res, w)
    return _push_entry!(f, i, r)
end

"""
    front_dominates(p, f, r) -> Bool

True when any stored label dominates `r` (port of `ParetoFrontValid::dominates`).

# Contracts
- `@ensures !result || any(k -> dominates(p, f.resource[k], r), eachindex(f.resource))`
"""
function front_dominates(p, f::ExtensibleFront{R}, r::R) where {R}
    res = f.resource
    @inbounds for k in eachindex(res)
        dominates(p, res[k], r) && return true
    end
    return false
end

# Consuming iteration: only entries still flagged extensible are yielded, and
# yielding clears the flag. (C++ ParetoFrontValid re-yielded the first entry of
# a non-empty front unconditionally; fixed here per the obvious intent.)
Base.iterate(f::ExtensibleFront) = _front_iterate(f, 0)
Base.iterate(f::ExtensibleFront, s::Int) = _front_iterate(f, s)

function _front_iterate(f::ExtensibleFront, s::Int)
    idx = f.index
    ext = f.extendable
    @inbounds for i in (s == 0 ? 1 : s + 1):length(idx)
        if ext[i]
            ext[i] = false
            return idx[i], i
        end
    end
    return nothing
end

"""
    EfficientFront{R}()

Per-node Pareto front of efficient labels; port of `rcspp::ParetoFrontNew`
(used by the path solver, which never iterates it — only dominance queries).
"""
mutable struct EfficientFront{R}
    index::Vector{Int}
    resource::Vector{R}
end
EfficientFront{R}() where {R} = EfficientFront{R}(Int[], R[])

@inline function _push_entry!(f::EfficientFront{R}, i::Integer, r::R) where {R}
    push!(f.index, i)
    push!(f.resource, r)
    return f
end

"""
    add_dominant!(p, f::EfficientFront, i, r) -> f

Drop entries dominated by candidate `r`, then append label `i` (order preserving).

# Contracts
- `@requires 1 <= i`
- `@ensures any(k -> f.index[k] == i, eachindex(f.index))`
- `@ensures !any(k -> dominates(p, r, f.resource[k]), eachindex(f.resource))`
"""
function add_dominant!(p, f::EfficientFront{R}, i::Integer, r::R) where {R}
    idx = f.index
    res = f.resource
    w = 0
    @inbounds for k in eachindex(idx)
        if !dominates(p, r, res[k])
            w += 1
            idx[w] = idx[k]
            res[w] = res[k]
        end
    end
    resize!(idx, w)
    resize!(res, w)
    return _push_entry!(f, i, r)
end

"""
    front_dominates(p, f::EfficientFront, r) -> Bool

True when any stored label dominates `r` (port of `ParetoFrontNew::dominates`).

# Contracts
- `@ensures !result || any(k -> dominates(p, f.resource[k], r), eachindex(f.resource))`
"""
function front_dominates(p, f::EfficientFront{R}, r::R) where {R}
    res = f.resource
    @inbounds for k in eachindex(res)
        dominates(p, res[k], r) && return true
    end
    return false
end
