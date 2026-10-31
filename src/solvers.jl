# Ports of EDF OSAK `algorithms/solvers/NodeSolver.hxx` (+ `NodeSolverData.hxx`)
# and `algorithms/solvers/PathSolver.hxx` (+ `PathSolverData.hxx`).
#
# SIMD design: when a label is popped, ALL of its out-arc extensions (the
# sub-paths) are evaluated in one batch into a preallocated scratch buffer
# (`_extend_batch!`); with `SVector` resources the loop is a packed vector add.
# Feasibility / filter / dominance checks then walk the batch in the exact arc
# order of the C++, so label creation order — and therefore the whole path
# table — is identical to the C++ solvers.

"""
    NodeSolver

Node-keyed label-setting solver, port of `rcspp::NodeSolver`. Nodes carry a
priority heap; popping a node extends every still-extensible efficient label
parked on it (one-shot consuming iteration of its [`ExtensibleFront`](@ref)).

Run with [`solve`](@ref): `solve(problem, NodeSolver, BasicFilter)`.
"""
struct NodeSolver end

"""
    PathSolver

Path-keyed label-setting solver, port of `rcspp::PathSolver`. Extensible labels
live in a priority heap (best-first for [`BoundedFilter`](@ref)); popped labels
are extended arc by arc, destination labels only update the incumbent.

Run with [`solve`](@ref): `solve(problem, PathSolver, BoundedFilter)`.
"""
struct PathSolver end

"""
    Solution{R,C}

Result of [`solve`](@ref): the complete [`PathTable`](@ref) of explored labels
plus the incumbent destination label.
"""
struct Solution{R,C}
    table::PathTable{R,C}
end

"Full label table of a solution."
paths(sol::Solution) = sol.table

"Node sequence of the incumbent path (empty when the destination is unreachable)."
node_path(sol::Solution) = sol.table.incumbent_index == 0 ? Int[] : node_path(sol.table, sol.table.incumbent_index)

"Arc sequence of the incumbent path (empty when the destination is unreachable)."
arc_path(sol::Solution) = sol.table.incumbent_index == 0 ? Int[] : arc_path(sol.table, sol.table.incumbent_index)

"Cost of the incumbent path (`typemax` when the destination is unreachable)."
incumbent_cost(sol::Solution) = incumbent_cost(sol.table)
"""
    _extend_batch!(dests, p, r, out_arc, lo, nout)

Batch-evaluates all out-arc extensions into `dests`.

# Contracts
- `@requires 0 <= nout`
"""
@inline function _extend_batch!(dests, p, r, out_arc, lo, nout)
    @inbounds @simd for j in 1:nout
        dests[j] = extend_resource(p, r, @inbounds(out_arc[lo + j]))
    end
end
# Preallocated scratch for batched sub-path extension, sized to the max
# out-degree of the graph.
function _dests_scratch(p::AbstractRCSProblem, R::Type)
    g = graph(p)
    maxdeg = 0
    @inbounds for v in 1:node_count(g)
        d = g.out_start[v + 1] - g.out_start[v]
        maxdeg = ifelse(d > maxdeg, d, maxdeg)
    end
    return Vector{R}(undef, maxdeg)
end

"""
    solve(problem, NodeSolver, BasicFilter) -> Solution
    solve(problem, NodeSolver, BoundedFilter) -> Solution
    solve(problem, PathSolver, BasicFilter) -> Solution
    solve(problem, PathSolver, BoundedFilter) -> Solution

Run a label-setting search for the resource-constrained shortest path of
`problem`, port of `rcspp::NodeSolver::solve` / `rcspp::PathSolver::solve`.
The graph must be [`close!`](@ref)d. Label creation order matches the C++
solvers; the returned [`Solution`](@ref) exposes `node_path`, `arc_path`,
`incumbent_cost` and the raw `paths` table.

# Contracts
- `@requires graph(p).closed`
- `@invariant table.incumbent_index == 0 || is_feasible(p, table.resource[table.incumbent_index], dest_node(p))`
- `@ensures isempty(node_path(result)) || node_path(result)[1] == source_node(p)`
- `@ensures isempty(node_path(result)) || node_path(result)[end] == dest_node(p)`
- `@ensures isempty(node_path(result)) || is_feasible(p, paths(result).resource[paths(result).incumbent_index], dest_node(p))`
- `@ensures isempty(node_path(result)) || (incumbent_cost(result) == resource_cost(paths(result).resource[paths(result).incumbent_index]))`
"""
function solve(p::AbstractRCSProblem, ::Type{NodeSolver}, ::Type{F}) where {F<:AbstractPathFilter}
    g = graph(p)
    g.closed || throw(ArgumentError("call close!(graph) before solving"))
    n = node_count(g)
    src = source_node(p)
    dst = dest_node(p)

    filter = F(p)
    r0 = initial_resource(p)
    R = typeof(r0)
    table = PathTable(r0, src)

    fronts = [ExtensibleFront{R}() for _ in 1:n]
    _push_entry!(fronts[src], 1, r0)

    P = typeof(node_priority(p, src))
    heap = PriorityHeap{Int,P}()
    init!(heap, src)
    in_heap = fill(false, n)
    in_heap[src] = true

    dests = _dests_scratch(p, R)

    while !isempty(heap)
        origin = pop!(heap)
        in_heap[origin] = false
        front = fronts[origin]
        lo = g.out_start[origin]
        nout = g.out_start[origin + 1] - lo
        for pi in front  # consuming iteration, C++ ParetoFrontValid semantics
            r = @inbounds table.resource[pi]
            _extend_batch!(dests, p, r, g.out_arc, lo, nout)
            @inbounds for j in 1:nout
                pos = lo + j
                dn = g.out_node[pos]
                dr = dests[j]
                is_feasible(p, dr, dn) || continue
                is_candidate(filter, p, dr, dn, table.incumbent_cost) || continue
                front_dominates(p, fronts[dn], dr) && continue
                np = add_path!(table, dr, dn, g.out_arc[pos], pi)
                add_dominant!(p, fronts[dn], np, dr)
                if dn != dst
                    if !in_heap[dn]
                        push!(heap, dn, node_priority(p, dn))
                        in_heap[dn] = true
                    end
                else
                    update_incumbent!(table, np)
                end
            end
        end
    end
    return Solution(table)
end

function solve(p::AbstractRCSProblem, ::Type{PathSolver}, ::Type{F}) where {F<:AbstractPathFilter}
    g = graph(p)
    g.closed || throw(ArgumentError("call close!(graph) before solving"))
    n = node_count(g)
    src = source_node(p)
    dst = dest_node(p)

    filter = F(p)
    r0 = initial_resource(p)
    R = typeof(r0)
    table = PathTable(r0, src)

    fronts = [EfficientFront{R}() for _ in 1:n]
    _push_entry!(fronts[src], 1, r0)

    P = typeof(path_priority(filter, p, r0, src))
    heap = PriorityHeap{Int,P}()
    init!(heap, 1)

    dests = _dests_scratch(p, R)

    while !isempty(heap)
        pi = pop!(heap)
        origin = @inbounds table.node[pi]
        r = @inbounds table.resource[pi]
        lo = g.out_start[origin]
        nout = g.out_start[origin + 1] - lo
        _extend_batch!(dests, p, r, g.out_arc, lo, nout)
        @inbounds for j in 1:nout
            pos = lo + j
            dn = g.out_node[pos]
            dr = dests[j]
            is_feasible(p, dr, dn) || continue
            is_candidate(filter, p, dr, dn, table.incumbent_cost) || continue
            front_dominates(p, fronts[dn], dr) && continue
            np = add_path!(table, dr, dn, g.out_arc[pos], pi)
            if dn != dst
                add_dominant!(p, fronts[dn], np, dr)
                push!(heap, np, path_priority(filter, p, dr, dn))
            else
                update_incumbent!(table, np)
            end
        end
    end
    return Solution(table)
end
