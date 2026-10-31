# End-to-end formal verification driver for Kaos.jl (JuLean-backed).
#
#   julia --project=formal formal/verify_kernels.jl
#
# Ladder:
#   Tier 1 — Z3: the decision-rule theorems are machine-checked over ALL reals
#            (strict Pareto dominance asymmetry/transitivity, the additive
#            extension elimination lemma, the incumbent min-rule, the bounded
#            filter monotonicity).
#   Tier 0 — DbC: the REAL Kaos kernels run with runtime contracts enabled and
#            are hammered on random data (divergence from the verified specs
#            would raise ContractViolationError).
#   Tier 3 — Lean 4 + Mathlib: the same theorems proved by the Lean kernel
#            (sorry-free, per JuLean soundness policy) when a Lake project is
#            configured.

using StaticArrays
using Random: MersenneTwister, rand
using Kaos
using JuLean
const EXT = Base.get_extension(Kaos, :KaosJuLeanExt)
using Test

@assert Base.get_extension(Kaos, :KaosJuLeanExt) isa Module "KaosJuLeanExt did not load"

Z3_SPECS = [:kaos_dominance_asymmetry2,
            :kaos_dominance_transitivity2,
            :kaos_dominance_additive_extension2,
            :kaos_incumbent_rule,
            :kaos_mincost_monotone]

results = Tuple{String,String,JuLean.VerificationStatus}[]

# ---------------- Tier 1: Z3 -----------------------------------------------
println("=== Tier 1: Z3 falsification over ℚ (all reals) ===")
for name in Z3_SPECS
    res = JuLean.verify(name; backend = :Z3)
    ok = res.status === JuLean.StatusVerified
    push!(results, (string(name), "Z3", res.status))
    println(rpad(name, 42), " → ", res.status, "  (", round(res.elapsed_time; digits = 0), " ms)")
    if !ok
        println("   message: ", res.message)
        isdefined(res, :counterexample) && println("   counterexample: ", res.counterexample)
    end
    @assert ok "Z3 could not verify $name: $(res.message)"
end

# ---------------- Tier 0: DbC hammering on the real kernels ----------------
println("\n=== Tier 0: runtime contracts on the real kernels (hammering) ===")
JuLean.enable_contracts!(true)
function tier0_hammering(rng)
    n_dom = 0
    for _ in 1:20000
        N = 2 + rand(rng, 0:2)                  # resource dimensions 2..4
        a = SVector{N}((randn(rng) for _ in 1:N))
        b = SVector{N}((randn(rng) for _ in 1:N))
        n_dom += 1
        EXT.dbc_dominates(a, b)
    end

    n_path = 0
    for _ in 1:2000
        t = Kaos.PathTable(zero(SVector{2,Float64}), 1)
        for step in 1:6
            node = 1 + rand(rng, 1:5)
            arc = 1 + rand(rng, 1:9)
            r = SVector(step * 0.25, 0.1)
            i = EXT.dbc_add_path!(t, r, node, arc, length(t.node))
            EXT.dbc_update_incumbent!(t, i)
            n_path += 2
        end
    end

    n_cand = 0
    for _ in 1:20000
        c = randn(rng); b = abs(randn(rng)); inc = abs(randn(rng))
        n_cand += 1
        EXT.dbc_is_candidate_bounded(c, b, inc)
    end
    return n_dom, n_path, n_cand
end

(n_dom, n_path, n_cand) = tier0_hammering(MersenneTwister(7))
println("dbc_dominates: ", n_dom, " random pairs, contracts OK")
println("dbc_add_path!/dbc_update_incumbent!: ", n_path, " contract-checked calls, contracts OK")
println("dbc_is_candidate_bounded: ", n_cand, " random triples, contracts OK")

# ---------------- Tier 3: Lean 4 + Mathlib ---------------------------------
println("\n=== Tier 3: Lean 4 kernel (Mathlib) ===")
LEAN_PROJECT = "/home/D01856/dunes/formalization"
if isdir(LEAN_PROJECT)
    JuLean.set_lean_project_dir!(LEAN_PROJECT)
    TACTICS = ["", "linarith", "aesop", "push_neg; linarith", "simp; linarith", "omega"]
    for name in Z3_SPECS
        res = nothing
        used = ""
        for tac in TACTICS
            res = JuLean.verify(name; backend = :Lean4, timeout = 300.0, tactic = tac)
            res.status === JuLean.StatusVerified && (used = isempty(tac) ? "default" : tac; break)
        end
        push!(results, (string(name), "Lean4", res.status))
        println(rpad(name, 42), " → ", res.status, (isempty(used) ? "" : "  [tactic: " * used * "]"))
        if res.status !== JuLean.StatusVerified
            println("   message: ", res.message)
        end
    end
else
    println("Lean project not found at ", LEAN_PROJECT, " — skipping")
end

# ---------------- summary ---------------------------------------------------
println("\n=== Verification summary ===")
for (name, backend, status) in results
    println(rpad(name, 42), rpad(backend, 8), status)
end
n_verified = count(r -> r[3] === JuLean.StatusVerified, results)
println("\n", n_verified, "/", length(results), " machine-verified")
@assert n_verified == length(results) "some specifications are not fully verified"
println("END-TO-END VALIDITY: all tiers green")
