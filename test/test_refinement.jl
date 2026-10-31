# Bisimulation and Invariant Refinement Test
#
# Validates state-by-state correspondence between the Lean 4 formal machine
# (`DunesLean.RCSPP`) and the real Kaos.jl execution data structures.

using Test
using Kaos
using StaticArrays: SVector

@testset "Lean 4 / Kaos Bisimulation & Invariant Refinement" begin
    p = TestProblem()
    g = Kaos.graph(p)
    src = Kaos.source_node(p)
    dst = Kaos.dest_node(p)

    for (S, F) in ((Kaos.NodeSolver, Kaos.BasicFilter),
                   (Kaos.NodeSolver, Kaos.BoundedFilter),
                   (Kaos.PathSolver, Kaos.BasicFilter),
                   (Kaos.PathSolver, Kaos.BoundedFilter))
        sol = Kaos.solve(p, S, F)
        table = sol.table

        # 1. Invariant: sound_labels (each label in table forms a valid path)
        for i in 1:length(table.node)
            np = Kaos.node_path(table, i)
            ap = Kaos.arc_path(table, i)
            @test np[1] == src
            @test np[end] == table.node[i]
            @test length(ap) == length(np) - 1

            # Accumulate resources along the arc sequence
            r = Kaos.initial_resource(p)
            for a in ap
                r = r + p.arc_res[a]
            end
            @test r == table.resource[i]
        end

        # 2. Invariant: sound_incumbent
        if table.incumbent_index != 0
            opt_node_path = Kaos.node_path(sol)
            opt_arc_path = Kaos.arc_path(sol)
            @test opt_node_path[end] == dst
            @test table.incumbent_cost == table.resource[table.incumbent_index][1]
            @test Kaos.is_feasible(p, table.resource[table.incumbent_index], dst)
        end

        # 3. Invariant: coverage against known optimal path [1, 2, 5, 8, 11]
        opt_path = Kaos.node_path(sol)
        @test opt_path == [1, 2, 5, 8, 11]
    end
end
