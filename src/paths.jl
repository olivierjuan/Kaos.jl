# Port of EDF OSAK `src/resource_constrained_shortest_path/algorithms/paths/Paths.hxx`.

"""
    PathTable{R,C}

Structure-of-arrays table of every label (partial path) explored by a solver,
port of `rcspp::Paths`. Row `i` encodes: label `i` ends at `node[i]`, was
obtained by extending label `parent[i]` over `arc[i]`, and carries
`resource[i]`. Row 1 is the root (source, empty path).

Cost type `C` is that of `resource_cost(resource[1])`.
"""
mutable struct PathTable{R,C}
    const resource::Vector{R}
    const node::Vector{Int}
    const arc::Vector{Int}
    const parent::Vector{Int}
    const children::Vector{Int}
    const paths_to_dest::Vector{Int}
    incumbent_cost::C
    incumbent_index::Int
end

function PathTable(r0::R, root::Integer) where {R}
    C = typeof(resource_cost(r0))
    return PathTable{R,C}([r0], [Int(root)], [0], [0], [0], Int[], typemax(C), 0)
end

"""
    add_path!(t::PathTable, r, node, arc, parent) -> Int

Append a label extending `parent` over `arc` into `node` with resource `r`
(port of `Paths::addPath`) and return its index.

# Contracts
- `@requires 1 <= parent <= length(t.node)`
- `@requires 1 <= node`
- `@requires 1 <= arc`
- `@ensures result == length(t.node)`
- `@ensures t.parent[result] == parent && t.node[result] == node && t.arc[result] == arc`
- `@ensures t.resource[result] == r`
- `@ensures t.children[parent] >= 1`
"""
@inline function add_path!(t::PathTable, r, node::Integer, arc::Integer, parent::Integer)
    push!(t.resource, r)
    push!(t.node, node)
    push!(t.arc, arc)
    push!(t.parent, parent)
    push!(t.children, 0)
    i = length(t.node)
    t.children[parent] += 1
    return i
end

"""
    update_incumbent!(t::PathTable, i::Int) -> Bool

Record label `i` as reaching the destination; adopt it as the incumbent when it
strictly improves the cost (first label wins ties, as in the C++). Returns
whether a new incumbent was adopted (port of `update_incumbent_path`).

# Contracts
- `@requires 1 <= i <= length(t.node)`
- `@ensures !result || (t.incumbent_index == i)`
- `@ensures t.incumbent_cost <= resource_cost(t.resource[i])`
"""
@inline function update_incumbent!(t::PathTable, i::Integer)
    candidate = resource_cost(t.resource[i])
    is_new = t.incumbent_index == 0 || t.incumbent_cost > candidate
    if is_new
        t.incumbent_cost = candidate
        t.incumbent_index = i
    end
    push!(t.paths_to_dest, i)
    return is_new
end

"Current incumbent cost (`typemax` when no destination was reached yet)."
incumbent_cost(t::PathTable) = t.incumbent_cost

# Reverse the parent chain from label `i` back to the root. The C++ skips the
# first element of the reversed deque for arcs (`first = 1`), which drops the
# root's dummy arc; node paths keep everything (`first = 0`).
function _chain(t::PathTable, i::Integer, getfield, skip_first::Bool)
    out = Int[]
    cur = i
    while cur != 0
        push!(out, getfield(cur))
        cur = t.parent[cur]
    end
    reverse!(out)
    skip_first && popfirst!(out)
    return out
end

"""
    node_path(t::PathTable, i::Int) -> Vector{Int}

Node sequence of the path ending at label `i`, source included.
"""
node_path(t::PathTable, i::Integer) = _chain(t, i, k -> t.node[k], false)

"""
    arc_path(t::PathTable, i::Int) -> Vector{Int}

Arc sequence of the path ending at label `i` (the root's placeholder arc is
dropped, as in the C++).
"""
arc_path(t::PathTable, i::Integer) = _chain(t, i, k -> t.arc[k], true)

"""
    path_argmin(t::PathTable, predicate) -> Vector{Int}

Node path of the terminal label (no children) minimising `predicate`, port of
`Paths::path_argmin`. `predicate(best_node, best_resource, candidate_node,
candidate_resource)` returns `true` when the candidate replaces the current
best; ties keep the earliest-created label, mirroring the C++ scan order.
Returns an empty vector when no terminal label exists.
"""
function path_argmin(t::PathTable, predicate)
    best = 0
    for i in eachindex(t.node)
        t.children[i] == 0 || continue
        if best == 0
            best = i
        else
            predicate(t.node[best], t.resource[best], t.node[i], t.resource[i]) &&
                (best = i)
        end
    end
    return best == 0 ? Int[] : node_path(t, best)
end
