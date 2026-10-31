# Formal verification test suite (JuLean + Z3 + Lean 4)
# Follows the Sirocco.jl integration standard.

using Test
using StaticArrays: SVector
using Random: MersenneTwister, rand, randn

dunes_candidates = [
    "/home/D01856/dunes",
    normpath(joinpath(@__DIR__, "..", "..", "dunes")),
    normpath(joinpath(@__DIR__, "..", "..", "..", "dunes")),
]
for d in dunes_candidates
    if isdir(d) && !(d in LOAD_PATH)
        push!(LOAD_PATH, d)
    end
end

using JuLean
using Kaos

@testset "Kaos Formal Verification (JuLean.jl)" begin

    # 1. Extension Verification
    @testset "1. Extension Initialization & Registry" begin
        EXT = Base.get_extension(Kaos, :KaosJuLeanExt)
        @test EXT isa Module

        for f in EXT.KERNEL_FUNCTIONS
            sname = nameof(f)
            @test haskey(JuLean.SPEC_REGISTRY, sname)
        end
    end

    # 2. Tier 1: Z3 SMT Verification Sweep
    @testset "2. Tier 1: Z3 Falsification over ℚ" begin
        Z3_SPECS = [
            :kaos_dominance_asymmetry2,
            :kaos_dominance_transitivity2,
            :kaos_dominance_additive_extension2,
            :kaos_incumbent_rule,
            :kaos_mincost_monotone
        ]
        for name in Z3_SPECS
            res = JuLean.verify(name; backend = :Z3)
            @test res.status === JuLean.StatusVerified
        end
    end

    # 3. Tier 0: DbC Hammering on Real Kernels
    @testset "3. Tier 0: DbC Hammering on Real Kernels" begin
        JuLean.enable_contracts!(true)
        rng = MersenneTwister(7)

        chk_dom = JuLean.contracted(Kaos.dominates)
        for _ in 1:5000
            N = 2 + rand(rng, 0:2)
            a = SVector{N}((randn(rng) for _ in 1:N))
            b = SVector{N}((randn(rng) for _ in 1:N))
            chk_dom(a, b)
        end

        chk_add = JuLean.contracted(Kaos.add_path!)
        chk_inc = JuLean.contracted(Kaos.update_incumbent!)
        for _ in 1:500
            t = Kaos.PathTable(zero(SVector{2,Float64}), 1)
            for step in 1:6
                node = 1 + rand(rng, 1:5)
                arc = 1 + rand(rng, 1:9)
                r = SVector(step * 0.25, 0.1)
                i = chk_add(t, r, node, arc, length(t.node))
                chk_inc(t, i)
            end
        end

        chk_cand = JuLean.contracted(Kaos.is_candidate)
        for _ in 1:5000
            c = randn(rng); b = abs(randn(rng)); inc = abs(randn(rng))
            chk_cand(Kaos.BoundedFilter([b]), nothing, SVector(c, 0.0), 1, inc)
        end
        @test true
    end

    # 4. Tier 2: BMC Verification
    @testset "4. Tier 2: BMC Array & Loop Verification" begin
        BMC_SPECS = [
            (:kaos_extend_batch_arr, 4),
            (:kaos_front_scan_arr, 4)
        ]
        for (name, depth) in BMC_SPECS
            res = JuLean.verify(name; backend = :BMC, depth = depth)
            @test res.status === JuLean.StatusVerified
        end
    end

    # 5. Tier 3: Lean 4 Kernel Sweep
    @testset "5. Tier 3: Lean 4 Kernel Verification (Mathlib)" begin
        LEAN_PROJECT = "/home/D01856/dunes/formalization"
        if isdir(LEAN_PROJECT)
            JuLean.set_lean_project_dir!(LEAN_PROJECT)
            LEAN_SPECS = [
                (:kaos_dominance_asymmetry2, ""),
                (:kaos_dominance_transitivity2, ""),
                (:kaos_dominance_additive_extension2, ""),
                (:kaos_mincost_monotone, ""),
                (:kaos_incumbent_adopt, ""),
                (:kaos_incumbent_improve, ""),
                (:kaos_incumbent_hold, ""),
                (:kaos_incumbent_rule,
                 "cases has_inc <;> simp [kaos_incumbent_rule] <;> by_cases h : prev > cand <;> simp [h] <;> linarith")
            ]
            for (name, tac) in LEAN_SPECS
                res = JuLean.verify(name; backend = :Lean4, timeout = 300.0, tactic = tac)
                @test res.status === JuLean.StatusVerified
            end
        end
    end
end
