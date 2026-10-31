using Kaos
using Documenter

makedocs(;
    modules = [Kaos],
    authors = "Olivier JUAN <olivier.juan@edf.fr>",
    sitename = "Kaos.jl",
    repo = "https://github.com/olivierjuan/Kaos.jl/blob/{commit}{path}#{line}",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://olivierjuan.github.io/Kaos.jl",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "API reference" => "api.md",
    ],
)

deploydocs(;
    repo = "github.com/olivierjuan/Kaos.jl",
    devbranch = "main",
)
