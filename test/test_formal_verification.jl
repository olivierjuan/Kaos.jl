# End-to-end validity proof (independent of JuLean, runs in plain CI).
#
# For each random instance, EVERY solver/filter combination must return an
# incumbent equal to the minimum cost over the COMPLETE feasible path set,
# computed by exhaustive enumeration — the only optimality argument that
# covers the whole search space. Paths are re-walked arc by arc, resources
# re-extended, and every prefix re-checked for feasibility. Unconstrained
# variants are cross-checked against an independent Dijkstra, and the A*
# lower bounds against an independent exact backward DP.

using Random: MersenneTwister
using StaticArrays: SVector

# ---- independent oracles (no Kaos solver machinery involved) ---------------

"Exhaustive DFS: (minimum feasible destination cost, number of feasible paths)."
function enumerate_feasible(arc_res::Vector{SVector{K,Float64}}, adj, src, dst, cap) where {K}
    mincost = Ref(Inf)
    nfeas = Ref(0)
    visit = function (v, r)
        if v == dst
            nfeas[] += 1
            r[1] < mincost[] && (mincost[] = r[1])
            return
        end
        for (w, a) in adj[v]
            r2 = r + arc_res[a]
            sum(r2[i] for i in 2:K) <= cap || continue
            visit(w, r2)
        end
    end
    visit(src, zero(SVector{K,Float64}))
    return mincost[], nfeas[]
end

"Independent Dijkstra over arc costs (O(n^2), no heap machinery shared with Kaos)."
function dijkstra_costs(weights::Vector{Float64}, adj, src)
    n = length(adj)
    dist = fill(Inf, n)
    dist[src] = 0.0
    done = falses(n)
    for _ in 1:n
        best = Inf
        u = 0
        for v in 1:n
            if !done[v] && dist[v] < best
                best = dist[v]
                u = v
            end
        end
        u == 0 && break
        done[u] = true
        for (w, a) in adj[u]
            dist[w] = min(dist[w], dist[u] + weights[a])
        end
    end
    return dist
end

"Independent exact min cost-to-destination per node (memoized DFS on the DAG)."
function exact_cost_to_dest(weights::Vector{Float64}, adj, dst)
    n = length(adj)
    memo = Vector{Union{Nothing,Float64}}(nothing, n)
    go = function (v)
        v == dst && return 0.0
        memo[v] !== nothing && return memo[v]
        best = Inf
        for (w, a) in adj[v]
            best = min(best, weights[a] + go(w))
        end
        memo[v] = best
        return best
    end
    return [go(v) for v in 1:n]
end

# ---- random layered problems ----------------------------------------------

mutable struct RandomRCSProblem{K} <: Kaos.AbstractRCSProblem
    g::Kaos.BasicDirectedGraph
    arc_res::Vector{SVector{K,Float64}}
    layer::Vector{Int}
    src::Int
    dst::Int
    cap::Float64
end

struct UnconstrainedRCS{K} <: Kaos.AbstractRCSProblem
    inner::RandomRCSProblem{K}
end

Kaos.graph(p::RandomRCSProblem) = p.g
Kaos.source_node(p::RandomRCSProblem) = p.src
Kaos.dest_node(p::RandomRCSProblem) = p.dst

for K in (2, 3)
    @eval begin
        Kaos.initial_resource(p::RandomRCSProblem{$K}) = zero(SVector{$K,Float64})
        Kaos.arc_resource(p::RandomRCSProblem{$K}, a) = p.arc_res[a]
        Kaos.is_feasible(p::RandomRCSProblem{$K}, r, n) = sum(r[i] for i in 2:$K) <= p.cap
        Kaos.node_priority(p::RandomRCSProblem{$K}, n) = -Float64(p.layer[n])
        Kaos.path_priority(p::RandomRCSProblem{$K}, r, n) = r[1]

        Kaos.graph(p::UnconstrainedRCS{$K}) = p.inner.g
        Kaos.source_node(p::UnconstrainedRCS{$K}) = p.inner.src
        Kaos.dest_node(p::UnconstrainedRCS{$K}) = p.inner.dst
        Kaos.initial_resource(p::UnconstrainedRCS{$K}) = zero(SVector{$K,Float64})
        Kaos.arc_resource(p::UnconstrainedRCS{$K}, a) = p.inner.arc_res[a]
        Kaos.is_feasible(p::UnconstrainedRCS{$K}, r, n) = true
        Kaos.node_priority(p::UnconstrainedRCS{$K}, n) = -Float64(p.inner.layer[n])
        Kaos.path_priority(p::UnconstrainedRCS{$K}, r, n) = r[1]
    end
end

function random_instance(rng; L, W, K)
    g = Kaos.BasicDirectedGraph()
    src = Kaos.add_node!(g)
    ids = [Int[] for _ in 1:L]
    for l in 1:L, _ in 1:W
        push!(ids[l], Kaos.add_node!(g))
    end
    dst = Kaos.add_node!(g)
    layer = zeros(Int, Kaos.node_count(g))
    for l in 1:L, v in ids[l]
        layer[v] = l
    end
    layer[dst] = L + 1

    arc_res = Vector{SVector{K,Float64}}()
    adj = [Tuple{Int,Int}[] for _ in 1:Kaos.node_count(g)]
    addar = function (s, t, c, cons...)
        a = Kaos.add_arc!(g, s, t)
        push!(arc_res, SVector{K}((c, cons...)))
        push!(adj[s], (t, a))
        return a
    end

    for l in 1:L, v in ids[l]
        if l <= L - 1
            nxt = ids[l+1]
            for _ in 1:(1 + (rand(rng) < 0.5 ? 1 : 0))
                t = nxt[rand(rng, 1:length(nxt))]
                addar(v, t, 0.5 + rand(rng), (rand(rng) * 0.6 for _ in 2:K)...)
            end
        else
            addar(v, dst, 0.5 + rand(rng), (rand(rng) * 0.6 for _ in 2:K)...)
        end
    end
    for l in 1:(L - 2), v in ids[l]
        if rand(rng) < 0.3
            t = ids[l+2][rand(rng, 1:W)]
            addar(v, t, 1.0 + rand(rng), (rand(rng) * 0.8 for _ in 2:K)...)
        end
    end
    for v in ids[1]
        addar(src, v, 0.5 + rand(rng), (rand(rng) * 0.6 for _ in 2:K)...)
    end
    Kaos.close!(g)

    full_length = L  # typical number of arcs on a source->dst path
    cap = round(full_length * (K - 1) * 0.3 * (0.7 + 0.7 * rand(rng)); digits = 2)
    return RandomRCSProblem(g, arc_res, layer, src, dst, cap), adj
end

# ---- the proof --------------------------------------------------------------

@testset "formal end-to-end: exhaustive-oracle optimality on 100 random instances" begin
    n_checked = 0
    for seed in 1:100
        rng = MersenneTwister(seed)
        K = seed % 2 == 0 ? 3 : 2
        L = 3 + (seed % 4)
        W = 2 + (seed % 3)
        p, adj = random_instance(rng; L, W, K)
        g = p.g
        weights = Float64[r[1] for r in p.arc_res]

        mincost, nfeas = enumerate_feasible(p.arc_res, adj, p.src, p.dst, p.cap)
        dist = dijkstra_costs(weights, adj, p.src)
        exact = exact_cost_to_dest(weights, adj, p.dst)

        @testset "seed=$seed (K=$K L=$L W=$W)" begin
            # A* lower bounds must equal the exact unconstrained cost-to-go
            bounds = Kaos.BoundedFilter(p).node_bounds
            @test all(v -> isapprox(bounds[v], exact[v]; rtol = 1e-12), 1:Kaos.node_count(g))

            pu = UnconstrainedRCS(p)
            for (S, F) in ((Kaos.NodeSolver, Kaos.BasicFilter),
                           (Kaos.NodeSolver, Kaos.BoundedFilter),
                           (Kaos.PathSolver, Kaos.BasicFilter),
                           (Kaos.PathSolver, Kaos.BoundedFilter))
                sol = Kaos.solve(p, S, F)
                if nfeas == 0
                    @test isempty(Kaos.node_path(sol))
                    @test isempty(Kaos.arc_path(sol))
                    @test Kaos.incumbent_cost(sol) == Inf
                else
                    # OPTIMALITY against the complete feasible set (exact float
                    # equality: the solver and the oracle accumulate each path
                    # cost in the same order)
                    @test Kaos.incumbent_cost(sol) == mincost
                    # PATH VALIDITY, re-walked independently
                    np = Kaos.node_path(sol)
                    ap = Kaos.arc_path(sol)
                    @test np[1] == p.src && np[end] == p.dst
                    @test length(ap) == length(np) - 1
                    r = Kaos.initial_resource(p)
                    @test Kaos.is_feasible(p, r, np[1])
                    for k in eachindex(ap)
                        a = ap[k]  # parallel arcs exist: walk the returned arc ids
                        @test Kaos.source(g, a) == np[k] && Kaos.target(g, a) == np[k+1]
                        r = r + p.arc_res[a]
                        @test Kaos.is_feasible(p, r, np[k+1])
                    end
                    @test r[1] == Kaos.incumbent_cost(sol)
                    n_checked += 1
                end
                # UNCONSTRAINED optimum must match independent Dijkstra
                solu = Kaos.solve(pu, S, F)
                @test Kaos.incumbent_cost(solu) ≈ dist[p.dst] rtol = 1e-12
            end
        end
    end
    @test n_checked ≥ 50  # most instances are feasible; the rest hit the nfeas==0 branch
end
