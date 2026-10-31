# API reference

## Graphs

```@docs
Kaos.BasicDirectedGraph
Kaos.add_node!
Kaos.add_arc!
Kaos.close!
Kaos.node_count
Kaos.arc_count
Kaos.source
Kaos.target
Kaos.out_arcs
Kaos.in_arcs
Kaos.find_arc
Kaos.topological_order
Kaos.is_dag
```

## Problems

```@docs
Kaos.AbstractRCSProblem
Kaos.graph
Kaos.source_node
Kaos.dest_node
Kaos.initial_resource
Kaos.arc_resource
Kaos.arc_cost
Kaos.extend_resource
Kaos.is_feasible
Kaos.dominates
Kaos.node_priority
Kaos.path_priority
Kaos.resource_cost
```

## Filters

```@docs
Kaos.AbstractPathFilter
Kaos.BasicFilter
Kaos.BoundedFilter
Kaos.mincost
```

## Solvers

```@docs
Kaos.NodeSolver
Kaos.PathSolver
Kaos.solve
Kaos.Solution
Kaos.paths
Kaos.node_path
Kaos.arc_path
Kaos.incumbent_cost
Kaos.path_argmin
Kaos.PathTable
Kaos.add_path!
Kaos.update_incumbent!
Kaos.node_path(::Kaos.PathTable, ::Integer)
Kaos.arc_path(::Kaos.PathTable, ::Integer)
```

## Fronts and heap (internal, documented for completeness)

```@docs
Kaos.ExtensibleFront
Kaos.EfficientFront
Kaos.add_dominant!
Kaos.front_dominates
Kaos.PriorityHeap
Kaos.init!
```
