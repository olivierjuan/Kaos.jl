# Julia port of EDF OSAK `src/resource_constrained_shortest_path/algorithms/utils/Heap.hxx`.
# `std::make_heap`/`pop_heap` with `operator<` on the priority pop the LARGEST
# priority first; this heap mirrors that contract.

import Base: push!, pop!, isempty

"""
    PriorityHeap{K,P}()

Binary heap of keys with priorities, port of `rcspp::Heap`. [`init!`](@ref)
seeds it, `push!(h, key, priority)` inserts, and `pop!(h)` removes and returns
the key with the **largest** priority (callers pass negated priorities to get
min-first behaviour, exactly like the C++ code built on `std::make_heap`).
"""
mutable struct PriorityHeap{K,P}
    const data::Vector{Tuple{P,K}}
end
PriorityHeap{K,P}() where {K,P} = PriorityHeap{K,P}(Tuple{P,K}[])

"""
    init!(h::PriorityHeap, key) -> h

Seed the heap with `key` at maximal priority (port of `Heap::init`, which pushes
`PriorityInterface::infinity()`).
"""
function init!(h::PriorityHeap{K,P}, key) where {K,P}
    empty!(h.data)
    push!(h.data, (typemax(P), key))
    return h
end

function push!(h::PriorityHeap{K,P}, key, priority) where {K,P}
    data = h.data
    push!(data, (priority, key))
    i = length(data)
    @inbounds while i > 1
        parent = i >> 1
        _prio(data[parent]) < _prio(data[i]) || break
        data[i], data[parent] = data[parent], data[i]
        i = parent
    end
    return h
end

function pop!(h::PriorityHeap{K}) where {K}
    data = h.data
    isempty(data) && throw(ArgumentError("heap is empty"))
    top = data[1]
    last = pop!(data)::Tuple
    if !isempty(data)
        data[1] = last
        n = length(data)
        i = 1
        @inbounds while true
            l = 2 * i
            l > n && break
            c = (l < n && _prio(data[l + 1]) > _prio(data[l])) ? l + 1 : l
            _prio(data[c]) > _prio(data[i]) || break
            data[i], data[c] = data[c], data[i]
            i = c
        end
    end
    return top[2]::K
end

isempty(h::PriorityHeap) = isempty(h.data)

@inline _prio(t::Tuple) = t[1]
