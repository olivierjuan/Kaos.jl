[![CI](https://github.com/olivierjuan/Kaos.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/olivierjuan/Kaos.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://olivierjuan.github.io/Kaos.jl/dev/)

# Kaos.jl

Resource-constrained shortest path (RCSPP) label-setting solvers for Julia —
a faithful, SIMD-accelerated port of EDF's OSAK C++ library
(`resource_constrained_shortest_path`, namespace `rcspp`).

Given a directed graph, a source, a destination and a resource that grows
along arcs, Kaos finds the cheapest feasible path (label-setting with Pareto
dominance pruning, optional A*-style bounded filtering).

**Validity**: solver outputs are proven optimal against exhaustive enumeration
of the complete feasible path set on randomized instances, and the
decision-rule theorems are machine-checked by Z3 and the Lean 4 kernel via
JuLean — see [FORMAL.md](FORMAL.md).

## Status
Alpha (0.1.0). Semantics mirror the C++ solvers (same label creation order,
same incumbent rule); see [Port notes](#port-notes).

## Quick start

```julia
using Kaos, StaticArrays

# 1. A problem: subtype Kaos.AbstractRCSProblem and implement the interface
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

# 2. Solve (four combinations, all ported from the C++ test suite)
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

## SIMD

Resources live in registers: the recommended resource type is a
`StaticArrays.SVector` (component 1 = cost). Two hot kernels are written for
SIMD execution:

- **Sub-path extension** — when a label is popped, all its out-arc extensions
  are batch-evaluated into a preallocated buffer (`_extend_batch!`, `@simd`
  over contiguous, CSR-packed arc resources): one packed vector add per label
  instead of per-arc scalar adds, with zero allocation.
- **Dominance** — componentwise `≤` over the resource vector is a `@simd`
  reduction, and Pareto fronts store resources contiguously for cache-friendly
  scans.

The label-creation order (and therefore every result, including tie-breaks)
is identical to the C++ solvers: batching only parallelises the arithmetic,
never the control flow.

## Port notes

- Faithful ports of `rcspp::NodeSolver`, `PathSolver`, `Paths`, `Heap`
  (max-priority pop, as `std::pop_heap`), `ParetoFrontValid`,
  `ParetoFrontNew`, `BasicPathFilter`, `BoundedPathFilter` and
  `BasicDirectedGraph` (1-based ids instead of 0-based).
- `ParetoFrontValid`'s consuming-iterator quirk (first entry of a non-empty
  front is always re-yielded, re-extending an already-extended label) is
  **fixed** in the port: an entry is extended at most once.
- **Dominance**: the default `dominates` follows `docs/main.dox` (strict
  Pareto: `≤` on every component **and** `<` on at least one), not the weaker
  `≤,≤` relation hard-coded in the C++ `TestProblem` — that weaker relation is
  kept as an explicit problem-level override for C++ test parity.
- `path_argmin` counts children for real (the C++ `NoCounter` short-circuit
  made every label look terminal); terminal means *no child label*.
- `ActionLog` is not ported: it is compiled out in the default C++ build
  (`STORE_ACTION_LOG` undefined).
- `NoParetoFront` / `OrderedParetoFront` (unused alternatives in the C++)
  and the Boost/LEMON graph adapters have no counterpart here.
- Graph cycles: the C++ `is_dag` was a `return true` stub; the port detects
  cycles and errors in `topological_order`.

## Attribution

Port of [OSAK](https://gitlab.pleiade.edf.fr/osiris/optimstore/osak),
copyright 2016-2023 EDF (Olivier Juan et al.).
