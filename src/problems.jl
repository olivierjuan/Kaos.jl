# Problem interface, port of the C++ `Problem` template requirements
# (see `tests_common/TestProblem.hxx` and the `RCSPProblem` pybind11 interface).

"""
    AbstractRCSProblem

Supertype for resource-constrained shortest path problems. A concrete problem
only needs to implement the required interface below; everything else has a
default.

Required methods:

| method | C++ counterpart |
|---|---|
| `graph(p)` | `Problem::graph` |
| `source_node(p)` | `get_source_node` |
| `dest_node(p)` | `get_dest_node` |
| `initial_resource(p)` | `get_initial_resource` |
| `arc_resource(p, a)` | per-arc resource consumed by `extend` |

Default hooks:

| method | default | C++ counterpart |
|---|---|---|
| `extend_resource(p, r, a)` | `r + arc_resource(p, a)` | `extend` |
| `is_feasible(p, r, n)` | `true` | `is_feasible` |
| `dominates(p, a, b)` | componentwise `≤` on resources | `dominates` |
| `node_priority(p, n)` | `0.0` | `getNodePriority` |
| `path_priority(p, r, n)` | *(must be implemented for a basic `PathSolver`)* | `getPathPriority` |

Resources are immutable values (any type with `+`, `resource_cost` and
`dominates` works); `StaticArrays.SVector` is the SIMD fast path: component 1
is the cost.
"""
abstract type AbstractRCSProblem end

"Cost of arc `a`, port of `Problem::arc_cost` (first resource component)."
@inline arc_cost(p, a) = resource_cost(arc_resource(p, a))

"""
    extend_resource(p, r, a) -> r'

Resource of the path extended by arc `a` from resource `r`. Default is the
additive extension of the C++ `TestProblem::extend`; override for non-linear
resource dynamics.
"""
@inline extend_resource(p, r, a) = r + arc_resource(p, a)

"""
    is_feasible(p, r, n) -> Bool

Feasibility of holding resource `r` at node `n` (port of `is_feasible`).

# Contracts
- `@requires 1 <= n`
"""
is_feasible(p, r, n) = true

"""
    dominates(p, a, b) -> Bool

Dominance of resource `a` over `b` (port of `Problem::dominates`). Defaults to
the componentwise [`dominates(a, b)`](@ref) on the resources themselves.
"""
dominates(p, a, b) = dominates(a, b)

"""
    node_priority(p, n)

Node selection priority, port of `getNodePriority`. The heap pops the largest
priority first, so negate to explore small-`x` layers first (the C++
`TestProblem` returns `-x`).
"""
node_priority(p, n) = 0.0

"""
    path_priority(p, r, n)

Label selection priority for the basic [`PathSolver`](@ref), port of
`getPathPriority`. The heap pops the largest priority first; the bounded filter
supplies `-(cost to go)` itself.
"""
function path_priority end

"""
    graph(p) -> BasicDirectedGraph

**Required** problem interface: the graph being searched (port of
`Problem::graph`). Must have been frozen with [`close!`](@ref).
"""
function graph end

"""
    source_node(p) -> Int

**Required** problem interface: the node paths start from (port of
`get_source_node`).
"""
function source_node end

"""
    dest_node(p) -> Int

**Required** problem interface: the node paths must reach (port of
`get_dest_node`).
"""
function dest_node end

"""
    initial_resource(p)

**Required** problem interface: the resource carried at the source (port of
`get_initial_resource`).
"""
function initial_resource end

"""
    arc_resource(p, a)

**Required** problem interface: the resource vector consumed by traversing arc
`a` (the per-arc data feeding [`extend_resource`](@ref) and [`arc_cost`](@ref)).
"""
function arc_resource end
