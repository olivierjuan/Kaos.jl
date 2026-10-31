# Ports of EDF OSAK `algorithms/paths/BasicPathFilter.hxx` and
# `algorithms/paths/BoundedPathFilter.hxx`.

"""
    AbstractPathFilter

Supertype of label filters, port of the C++ `PATH_FILTER` template parameter.
A filter implements:

- `is_candidate(filter, problem, resource, node, incumbent)` — accept/reject a
  feasible extension (port of `isCandidate`);
- `path_priority(filter, problem, resource, node)` — heap priority for the
  path solver (port of `getPathPriority`);
- `node_priority(filter, problem, node)` — node priority for the node solver,
  delegated to `node_priority(problem, node)` by both shipped filters.
"""
abstract type AbstractPathFilter end

"""
    BasicFilter()

Accepts every feasible extension, port of `rcspp::PathFilter`. Path priority
delegates to `path_priority(problem, r, n)`.
"""
struct BasicFilter <: AbstractPathFilter end
BasicFilter(p::AbstractRCSProblem) = BasicFilter()  # uniform `filter(problem)` construction
@inline is_candidate(::BasicFilter, p, r, n, incumbent) = true

path_priority(::BasicFilter, p, r, n) = path_priority(p, r, n)

"Node priority shared by both filters (delegates to the problem)."
node_priority(::AbstractPathFilter, p, n) = node_priority(p, n)

"""
    BoundedFilter(p::AbstractRCSProblem)

A*-style filter, port of `rcspp::BoundedPathFilter`. Precomputes, for every
node, a lower bound `node_bounds[n]` on the cost of reaching the destination
(backward DP over the topological order, so `p` must be a DAG), then rejects
extensions whose `resource_cost + node_bounds[node]` already reaches the
incumbent. Path priority is `-(cost to go)`.
"""
struct BoundedFilter{C} <: AbstractPathFilter
    node_bounds::Vector{C}
end
BoundedFilter(p) = BoundedFilter(_backward_bounds(p))

function _backward_bounds(p)
    g = graph(p)
    g.closed || throw(ArgumentError("graph must be closed before filtering"))
    m = arc_count(g)
    C = if m == 0
        typeof(resource_cost(initial_resource(p)))
    else
        typeof(arc_cost(p, 1))
    end
    bounds = fill(typemax(C), node_count(g))
    bounds[dest_node(p)] = zero(C)
    # `topological_order` lists successors before predecessors, the exact
    # direction `computeBounds` needs: when a node is processed its bound is
    # final and propagates to its predecessors.
    order = topological_order(g)
    @inbounds for k in eachindex(order)
        n = order[k]
        mc = bounds[n]
        for pos in (g.in_start[n] + 1):g.in_start[n + 1]
            a = g.in_arc[pos]
            s = g.in_node[pos]
            v = mc + arc_cost(p, a)
            bounds[s] = min(bounds[s], v)
        end
    end
    return bounds
end

"Lower bound of the total cost of any completion of resource `r` at node `n`."
@inline mincost(f::BoundedFilter, r, n) = resource_cost(r) + f.node_bounds[n]

"""
    is_candidate(f::BoundedFilter, p, r, n, incumbent) -> Bool

True when `mincost(f, r, n) < incumbent`.

# Contracts
- `@requires incumbent >= 0`
- `@ensures result == (resource_cost(r) + f.node_bounds[n] < incumbent)`
"""
@inline function is_candidate(f::BoundedFilter, p, r, n, incumbent)
    return mincost(f, r, n) < incumbent
end

path_priority(f::BoundedFilter, p, r, n) = -mincost(f, r, n)
