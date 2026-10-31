# Julia port of EDF OSAK `src/resource_constrained_shortest_path/graphs/DirectedGraph.hxx`
# and `graphs/AbstractGraphInterface.hxx` (native `BasicDirectedGraph` only; the Boost
# and LEMON adapters are C++-specific and have no Julia counterpart).

"""
    BasicDirectedGraph()

Directed graph with contiguous 1-based node and arc identifiers, port of
`rcspp::BasicDirectedGraph`.

Build with [`add_node!`](@ref) / [`add_arc!`](@ref), then freeze the adjacency
with [`close!`](@ref). Nodes and arcs are numbered in creation order; arcs are
kept in ascending identifier order inside each adjacency list.

The adjacency is stored in CSR form (`out_start`/`out_arc`/`out_node` and
`in_start`/`in_arc`/`in_node`, 0-based offsets into 1-based position arrays),
which keeps the solver hot loop allocation-free.
"""
mutable struct BasicDirectedGraph
    const node_count::Int
    closed::Bool
    const arc_src::Vector{Int}
    const arc_dst::Vector{Int}
    out_start::Vector{Int}
    out_arc::Vector{Int}
    out_node::Vector{Int}
    in_start::Vector{Int}
    in_arc::Vector{Int}
    in_node::Vector{Int}

    BasicDirectedGraph() =
        new(0, false, Int[], Int[], Int[], Int[], Int[], Int[], Int[], Int[])
end

"Number of nodes, port of `node_number()`."
node_count(g::BasicDirectedGraph) = g.node_count

"Number of arcs, port of `arc_number()`."
arc_count(g::BasicDirectedGraph) = length(g.arc_src)

"""
    add_node!(g::BasicDirectedGraph) -> Int

Append a node and return its identifier (1-based). The graph must be open.
"""
function add_node!(g::BasicDirectedGraph)
    g.closed && error("cannot add nodes to a closed graph")
    return g.node_count += 1
end

"""
    add_arc!(g::BasicDirectedGraph, s, t) -> Int

Append an arc `s -> t` and return its identifier (1-based). The graph must be open.
"""
function add_arc!(g::BasicDirectedGraph, s::Integer, t::Integer)
    g.closed && error("cannot add arcs to a closed graph")
    1 <= s <= g.node_count || BoundsError(g, s)
    1 <= t <= g.node_count || BoundsError(g, t)
    push!(g.arc_src, s)
    push!(g.arc_dst, t)
    return length(g.arc_src)
end

# Counting sort of arcs by `row` (arc ids stay ascending within each row,
# matching the C++ `close()` which walks arcs in id order).
function _build_csr(row::Vector{Int}, companion::Vector{Int}, n::Int)
    m = length(row)
    start = zeros(Int, n + 1)
    @inbounds for a in 1:m
        start[row[a] + 1] += 1
    end
    @inbounds for i in 2:(n + 1)
        start[i] += start[i - 1]
    end
    ids = Vector{Int}(undef, m)
    nodes = Vector{Int}(undef, m)
    cursor = start[1:n]
    @inbounds for a in 1:m
        r = row[a]
        cursor[r] += 1
        ids[cursor[r]] = a
        nodes[cursor[r]] = companion[a]
    end
    return start, ids, nodes
end

"""
    close!(g::BasicDirectedGraph) -> BasicDirectedGraph

Freeze the graph and build the CSR adjacency (port of `close()`). Idempotent.
"""
function close!(g::BasicDirectedGraph)
    g.closed && return g
    n = g.node_count
    g.out_start, g.out_arc, g.out_node = _build_csr(g.arc_src, g.arc_dst, n)
    g.in_start, g.in_arc, g.in_node = _build_csr(g.arc_dst, g.arc_src, n)
    g.closed = true
    return g
end

"Source node of arc `a`."
source(g::BasicDirectedGraph, a::Integer) = g.arc_src[a]

"Target node of arc `a`."
target(g::BasicDirectedGraph, a::Integer) = g.arc_dst[a]

"Outgoing arcs of node `n` in ascending id order (requires a closed graph)."
function out_arcs(g::BasicDirectedGraph, n::Integer)
    g.closed || error("graph is not closed")
    return @view g.out_arc[(g.out_start[n] + 1):g.out_start[n + 1]]
end

"Incoming arcs of node `n` in ascending id order (requires a closed graph)."
function in_arcs(g::BasicDirectedGraph, n::Integer)
    g.closed || error("graph is not closed")
    return @view g.in_arc[(g.in_start[n] + 1):g.in_start[n + 1]]
end

"""
    find_arc(g::BasicDirectedGraph, s, t) -> Union{Int,Nothing}

First arc `s -> t` if any, port of `find_arc` (out-parameter becomes `nothing`).
"""
function find_arc(g::BasicDirectedGraph, s::Integer, t::Integer)
    for a in out_arcs(g, s)
        g.arc_dst[a] == t && return a
    end
    return nothing
end

# Iterative postorder DFS over the CSR adjacency. `order` ends up with every
# node appearing after all its successors (the exact direction the C++
# `topologicalOrder` produces and `BoundedPathFilter::computeBounds` relies on).
# Cycle detection is an intentional improvement over the C++ `is_dag` stub
# (which always returned `true`): on a cycle this returns `nothing` or errors.
function _dfs_order(g::BasicDirectedGraph, on_cycle::Symbol)
    n = g.node_count
    color = fill(0, n)  # 0 unvisited, 1 on stack, 2 done
    order = Vector{Int}(undef, n)
    idx = 0
    cursor = Vector{Int}(undef, n)
    stack = Vector{Int}()
    @inbounds for s in 1:n
        color[s] == 0 || continue
        empty!(stack)
        push!(stack, s)
        color[s] = 1
        cursor[s] = g.out_start[s]
        while !isempty(stack)
            v = stack[end]
            hi = g.out_start[v + 1]
            pos = cursor[v]
            descended = false
            while pos < hi
                w = g.out_node[pos + 1]
                pos += 1
                if color[w] == 0
                    cursor[v] = pos
                    color[w] = 1
                    cursor[w] = g.out_start[w]
                    push!(stack, w)
                    descended = true
                    break
                elseif color[w] == 1
                    on_cycle === :error &&
                        error("graph contains a cycle through node $w; a DAG is required")
                    return nothing
                end
            end
            cursor[v] = pos
            if !descended
                color[v] = 2
                idx += 1
                order[idx] = v
                pop!(stack)
            end
        end
    end
    return order
end

"""
    topological_order(g::BasicDirectedGraph) -> Vector{Int}

Postorder DFS listing where every node appears after all its successors, port of
`BasicGraphInterface::topologicalOrder`. Errors if the graph has a cycle.
"""
topological_order(g::BasicDirectedGraph) = _dfs_order(g, :error)

"""
    is_dag(g::BasicDirectedGraph) -> Bool

True when the graph is acyclic (real check; the C++ `is_dag` was an
always-true stub marked FIXME).
"""
is_dag(g::BasicDirectedGraph) = _dfs_order(g, :quiet) !== nothing
