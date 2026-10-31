using Test
using Kaos
using StaticArrays: SVector

include("testproblem.jl")
include("test_formal_verification.jl")

"""
    ReachabilityProblem

Minimal two-node-difference problem used to check unreachable destinations.
"""
mutable struct ReachabilityProblem <: Kaos.AbstractRCSProblem
    g::Kaos.BasicDirectedGraph
    src::Int
    dst::Int
end
Kaos.graph(p::ReachabilityProblem) = p.g
Kaos.source_node(p::ReachabilityProblem) = p.src
Kaos.dest_node(p::ReachabilityProblem) = p.dst
Kaos.initial_resource(p::ReachabilityProblem) = SVector(0.0, 0.0)
Kaos.arc_resource(p::ReachabilityProblem, a) = SVector(1.0, 0.0)

@testset "BasicDirectedGraph" begin
    p = TestProblem()
    g = Kaos.graph(p)
    @test Kaos.node_count(g) == 11
    @test Kaos.arc_count(g) == 26
    @test Kaos.is_dag(g)
    @test Kaos.source(g, 1) == 1 && Kaos.target(g, 1) == 2
    @test Kaos.find_arc(g, 3, 6) == 8  # C++ arc (n3, n6) is the 8th added arc
    @test Kaos.find_arc(g, 6, 3) === nothing
    @test length(Kaos.out_arcs(g, 3)) == 4
    @test length(Kaos.in_arcs(g, 6)) == 5
    topo = Kaos.topological_order(g)
    @test sort(topo) == collect(1:11)
    pos = Dict(n => i for (i, n) in enumerate(topo))
    @test all(pos[Kaos.target(g, a)] < pos[Kaos.source(g, a)] for a in 1:Kaos.arc_count(g))  # successors first, as in the C++
    @testset "cycle rejection" begin
        bad = Kaos.BasicDirectedGraph()
        a = Kaos.add_node!(bad); b = Kaos.add_node!(bad)
        Kaos.add_arc!(bad, a, b)
        Kaos.add_arc!(bad, b, a)
        Kaos.close!(bad)
        @test !Kaos.is_dag(bad)
        @test_throws ErrorException Kaos.topological_order(bad)
    end
end

@testset "BoundedFilter bounds are exact" begin
    p = TestProblem()
    bounds = Kaos._backward_bounds(p)
    oracle = exact_bounds_oracle(p)
    @test bounds ≈ oracle atol = 1e-12
end

const BEST_NODES = [1, 2, 5, 8, 11]  # C++ assert_best_path

@testset "incumbent path [1,2,5,8,11] on all solver/filter combinations" begin
    p = TestProblem()
    oracle_cost, oracle_nodes, oracle_arcs = best_path_oracle(p)

    for (S, F) in ((Kaos.NodeSolver, Kaos.BasicFilter),
                   (Kaos.NodeSolver, Kaos.BoundedFilter),
                   (Kaos.PathSolver, Kaos.BasicFilter),
                   (Kaos.PathSolver, Kaos.BoundedFilter))
        sol = Kaos.solve(p, S, F)
        @testset "$(S) × $(F)" begin
            @test Kaos.node_path(sol) == BEST_NODES
            @test Kaos.node_path(sol) == oracle_nodes
            @test Kaos.incumbent_cost(sol) ≈ oracle_cost rtol = 1e-12
            # arc path consistent with the node path
            apath = Kaos.arc_path(sol)
            @test length(apath) == length(BEST_NODES) - 1
            g = Kaos.graph(p)
            for k in eachindex(apath)
                a = Kaos.find_arc(g, BEST_NODES[k], BEST_NODES[k+1])
                @test a == apath[k]
            end
            # final resource matches incremental extension
            r = Kaos.initial_resource(p)
            for a in apath
                r = Kaos.extend_resource(p, r, a)
            end
            @test Kaos.resource_cost(r) ≈ Kaos.incumbent_cost(sol) rtol = 1e-12
            # budget respected (the value-100 trap never triggers)
            @test r[2] <= 4.0
        end
    end
end

@testset "BoundedFilter actually prunes" begin
    p = TestProblem()
    basic = Kaos.solve(p, Kaos.PathSolver, Kaos.BasicFilter)
    bounded = Kaos.solve(p, Kaos.PathSolver, Kaos.BoundedFilter)
    # same optimum...
    @test Kaos.incumbent_cost(basic) ≈ Kaos.incumbent_cost(bounded) rtol = 1e-12
    # ...from a strictly smaller (or equal) label table
    @test length(Kaos.paths(bounded).node) <= length(Kaos.paths(basic).node)
end

@testset "path_argmin over terminal labels" begin
    p = TestProblem()
    sol = Kaos.solve(p, Kaos.PathSolver, Kaos.BasicFilter)
    table = Kaos.paths(sol)
    yof(n) = p.coords[n][2]
    pred = (no, ro, nd, rd) -> yof(no) < yof(nd)  # C++ MonFonctor
    got = Kaos.path_argmin(table, pred)
    # oracle: first-created terminal label whose end node has maximal y
    terminals = [i for i in eachindex(table.node) if table.children[i] == 0]
    @test !isempty(terminals)
    best_i = 0
    for i in terminals
        if best_i == 0 || yof(table.node[best_i]) < yof(table.node[i])
            best_i = i
        end
    end
    @test got == Kaos.node_path(table, best_i)
    @test !isempty(got) && got[1] == 1
end

Kaos.arc_resource(::Nothing, s) = s  # additive stub so the default extend applies in the kernel test

@testset "SIMD kernels agree with scalar reference" begin
    N = 8
    rs = [randn(SVector{N,Float64}) for _ in 1:257]
    ss = [randn(SVector{N,Float64}) for _ in 1:257]
    dests = Vector{SVector{N,Float64}}(undef, 257)
    Kaos._extend_batch!(dests, nothing, rs[1], ss, 0, 257)  # additive default: p unused
    @test all(Kaos.dominates(a, b) == (all(a .<= b) && any(a .< b)) for a in rs, b in ss)
end

@testset "unreachable destination" begin
    g = Kaos.BasicDirectedGraph()
    a = Kaos.add_node!(g); b = Kaos.add_node!(g); c = Kaos.add_node!(g)
    Kaos.add_arc!(g, a, b)
    Kaos.close!(g)
    problem = ReachabilityProblem(g, 1, 3)
    sol = Kaos.solve(problem, Kaos.NodeSolver, Kaos.BasicFilter)
    @test isempty(Kaos.node_path(sol))
    @test isempty(Kaos.arc_path(sol))
    @test Kaos.incumbent_cost(sol) == typemax(Float64)
end

