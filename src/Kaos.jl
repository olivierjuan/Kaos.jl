module Kaos

using StaticArrays

# Zero-overhead contract macros in production; extracted by JuLean when loaded
macro invariant(cond)
    return esc(:(nothing))
end
macro requires(cond)
    return esc(:(nothing))
end
macro ensures(cond)
    return esc(:(nothing))
end

include("graphs.jl")
include("heap.jl")
include("resources.jl")
include("problems.jl")
include("paths.jl")
include("pareto.jl")
include("filters.jl")
include("solvers.jl")

end
