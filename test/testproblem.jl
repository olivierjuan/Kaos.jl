# Julia port of EDF OSAK `tests/tests_common/TestProblem.hxx` (11-node layered
# DAG with the value-100 trap out of node 4 and the `value <= 4` budget).

using StaticArrays: SVector

mutable struct TestProblem <: Kaos.AbstractRCSProblem
    const g::Kaos.BasicDirectedGraph
    const coords::Vector{NTuple{2,Float64}}
    const arc_res::Vector{SVector{2,Float64}}
end

function TestProblem()
    xs = (0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0)
    ys = (0.0, 0.2, 0.5, 0.8, 1.0)

    g = Kaos.BasicDirectedGraph()
    coords = NTuple{2,Float64}[]
    add = function (x, y)
        push!(coords, (x, y))
        Kaos.add_node!(g)
    end
    n1 = add(xs[2], ys[3])   # C++ (xs[1], ys[2])
    n2 = add(xs[3], ys[2])
    n3 = add(xs[3], ys[3])
    n4 = add(xs[3], ys[4])
    n5 = add(xs[4], ys[2])
    n6 = add(xs[4], ys[3])
    n7 = add(xs[4], ys[4])
    n8 = add(xs[5], ys[2])
    n9 = add(xs[5], ys[3])
    n10 = add(xs[6], ys[4])
    n11 = add(xs[7], ys[3])
    @assert n1 == 1 && n11 == 11

    arcs = [
        (n1, n2), (n1, n3), (n1, n4),
        (n2, n5), (n2, n6),
        (n3, n2), (n3, n5), (n3, n6), (n3, n7),
        (n4, n3), (n4, n6), (n4, n7),
        (n5, n6), (n5, n8), (n5, n9),
        (n6, n8), (n6, n9), (n6, n10),
        (n7, n6), (n7, n9), (n7, n10),
        (n8, n11), (n8, n9),
        (n9, n11), (n9, n10),
        (n10, n11),
    ]
    arc_res = SVector{2,Float64}[]
    for (s, t) in arcs
        x_s, y_s = coords[s]
        x_t, y_t = coords[t]
        dx = x_t - x_s
        dy = y_t - y_s
        c = sqrt(dx * dx + dy * dy) + y_t + Float64(t - 1)  # C++ adds the 0-based target index
        v = s == 4 ? 100.0 : 1.0  # every arc out of node 4 is infeasible in practice
        push!(arc_res, SVector(c, v))
    end
    Kaos.close!(g)
    return TestProblem(g, coords, arc_res)
end

Kaos.graph(p::TestProblem) = p.g
Kaos.source_node(p::TestProblem) = 1
Kaos.dest_node(p::TestProblem) = 11
Kaos.initial_resource(p::TestProblem) = SVector(0.0, 0.0)
Kaos.arc_resource(p::TestProblem, a) = p.arc_res[a]
Kaos.is_feasible(p::TestProblem, r, n) = r[2] <= 4.0
Kaos.node_priority(p::TestProblem, n) = -p.coords[n][1]
Kaos.path_priority(p::TestProblem, r, n) = r[2]

"""
    best_path_oracle(p::TestProblem) -> (cost, nodes, arcs)

Exhaustive DFS over the DAG: cheapest feasible source→destination path.
Independent ground truth for the solvers.
"""
function best_path_oracle(p::TestProblem)
    g = p.g
    best_cost = Inf
    best_nodes = Int[]
    best_arcs = Int[]
    nodes = Int[1]
    arcs = Int[]
    resource = Kaos.initial_resource(p)
    function visit(v, r)
        if v == Kaos.dest_node(p)
            if Kaos.resource_cost(r) < best_cost
                best_cost = Kaos.resource_cost(r)
                best_nodes = copy(nodes)
                best_arcs = copy(arcs)
            end
            return
        end
        for a in Kaos.out_arcs(g, v)
            w = Kaos.target(g, a)
            r2 = Kaos.extend_resource(p, r, a)
            Kaos.is_feasible(p, r2, w) || continue
            push!(nodes, w)
            push!(arcs, a)
            visit(w, r2)
            pop!(nodes)
            pop!(arcs)
        end
    end
    visit(1, resource)
    return best_cost, best_nodes, best_arcs
end

# Exact cost-to-destination lower bound per node (brute force), to validate
# `BoundedFilter.node_bounds` (the backward DP must be tight on a DAG).
function exact_bounds_oracle(p::TestProblem)
    g = p.g
    n = Kaos.node_count(g)
    bounds = fill(Inf, n)
    bounds[Kaos.dest_node(p)] = 0.0
    for v in 1:n
        v == Kaos.dest_node(p) && continue
        best = Inf
        nodes = Int[v]
        arcs = Int[]
        function visit(u, r)
            if u == Kaos.dest_node(p)
                best = min(best, Kaos.resource_cost(r))
                return
            end
            for a in Kaos.out_arcs(g, u)
                w = Kaos.target(g, a)
                r2 = Kaos.extend_resource(p, r, a)
                push!(nodes, w)
                push!(arcs, a)
                visit(w, r2)
                pop!(nodes)
                pop!(arcs)
            end
        end
        visit(v, Kaos.initial_resource(p))
        bounds[v] = best
    end
    return bounds
end
