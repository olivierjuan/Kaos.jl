module Kaos

using StaticArrays

# Formal verification hooks (implemented by KaosJuLeanExt when JuLean is loaded)
function verify_formal_specifications end
function export_lean_specifications end

export verify_formal_specifications, export_lean_specifications


include("graphs.jl")
include("heap.jl")
include("resources.jl")
include("problems.jl")
include("paths.jl")
include("pareto.jl")
include("filters.jl")
include("solvers.jl")

end
