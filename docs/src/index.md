# Kaos.jl

Resource-constrained shortest path (RCSPP) label-setting solvers for Julia —
a faithful, SIMD-accelerated port of EDF's OSAK C++ library
(`resource_constrained_shortest_path`, namespace `rcspp`).

Given a directed graph, a source, a destination and a resource that grows
along arcs, Kaos finds the cheapest feasible path: label-setting with Pareto
dominance pruning, optional A*-style bounded filtering.

## Problem interface

Subtype `Kaos.AbstractRCSProblem` and implement the required methods
(`graph`, `source_node`, `dest_node`, `initial_resource`, `arc_resource`);
extension, feasibility, dominance and priorities have defaults. The SIMD fast
path uses `StaticArrays.SVector` resources whose first component is the cost.

## Quick start

```julia
using Kaos, StaticArrays

struct Problem <: Kaos.AbstractRCSProblem
    g::Kaos.BasicDirectedGraph
    arc_res::Vector{SVector{2,Float64}}   # component 1 = cost, 2 = consumption
end

Kaos.graph(p) = p.g
Kaos.source_node(p) = 1
Kaos.dest_node(p) = 10
Kaos.initial_resource(p) = SVector(0.0, 0.0)
Kaos.arc_resource(p, a) = p.arc_res[a]
Kaos.is_feasible(p, r, n) = r[2] <= 4.0      # budget on the consumption

sol = Kaos.solve(p, Kaos.NodeSolver, Kaos.BoundedFilter)
Kaos.node_path(sol)       # incumbent path as nodes
Kaos.arc_path(sol)        # incumbent path as arcs
Kaos.incumbent_cost(sol)  # cost of the incumbent
Kaos.paths(sol)           # full label table (PathTable)
```

## Solvers and filters

| | `BasicFilter` | `BoundedFilter` |
|---|---|---|
| `NodeSolver` | pure label-setting | + backward cost bounds (DAG) |
| `PathSolver` | best-first on `path_priority` | best-first on `-(cost to go)` |

`BoundedFilter` requires a DAG (backward DP over the topological order).
Both solvers accept both filters; all four combinations are tested.

## SIMD

Resources live in registers (`SVector`). Two hot kernels are written for SIMD
execution:

- **Sub-path extension** — when a label is popped, all its out-arc extensions
  are batch-evaluated into a preallocated buffer (`_extend_batch!`, zero
  allocation, packed vector adds over CSR-contiguous arc ids).
- **Dominance** — componentwise `≤` / `<` over the resource vector, statically
  unrolled by StaticArrays; Pareto fronts store resources contiguously for
  cache-friendly scans.

Label creation order (and therefore every result, including tie-breaks)
matches the C++ solvers: batching only parallelises the arithmetic, never the
control flow.

## Where to go next

- [API reference](@ref) for every exported function;
- the repository `README.md` for port notes relative to the C++ original.
