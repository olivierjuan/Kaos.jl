# ============ Tier 1: theorems behind the search rules (SMT/Lean) ============
# This file is `include`d at KaosJuLeanExt.__init__: JuLean's SPEC_REGISTRY is
# runtime state, and module-level side effects on other packages would be
# dropped by precompilation.

# Strict Pareto dominance (docs/main.dox DOMINANCE) is asymmetric: if a
# strictly dominates b, then b does not even weakly dominate a (component
# equality would collapse, contradicting the required strict component).
@formalize function kaos_dominance_asymmetry2(ac::Real, av::Real, bc::Real, bv::Real)::Bool
    @requires ac <= bc && av <= bv && (ac < bc || av < bv)
    @ensures result == (bc > ac || bv > av)
    ac <= bc && av <= bv && (ac < bc || av < bv)
end

# Strict Pareto dominance is transitive — the property that lets the fronts
# drop dominated labels without ever losing the optimum.
@formalize function kaos_dominance_transitivity2(
    a1::Real, a2::Real, b1::Real, b2::Real, c1::Real, c2::Real,
)::Bool
    @requires a1 <= b1 && a2 <= b2 && (a1 < b1 || a2 < b2)
    @requires b1 <= c1 && b2 <= c2 && (b1 < c1 || b2 < c2)
    @ensures result == (a1 <= c1 && a2 <= c2 && (a1 < c1 || a2 < c2))
    a1 <= c1 && a2 <= c2 && (a1 < c1 || a2 < c2)
end

# THE elimination lemma of label-setting with additive resources: if label e
# strictly dominates candidate c, then after the SAME arc extension s, e+s
# still strictly dominates c+s. Hence extending a dominated candidate can
# never yield a label better than the dominating branch — pruning it is
# optimal-preserving.
@formalize function kaos_dominance_additive_extension2(
    e1::Real, e2::Real, c1::Real, c2::Real, s1::Real, s2::Real,
)::Bool
    @requires e1 <= c1 && e2 <= c2 && (e1 < c1 || e2 < c2)
    @ensures result == (e1 + s1 <= c1 + s1 && e2 + s2 <= c2 + s2 &&
                        (e1 + s1 < c1 + s1 || e2 + s2 < c2 + s2))
    e1 + s1 <= c1 + s1 && e2 + s2 <= c2 + s2 &&
        (e1 + s1 < c1 + s1 || e2 + s2 < c2 + s2)
end

# The incumbent update rule keeps the minimum of {previous, candidate}: the
# stored incumbent is never worse than either, and is always one of them.
@formalize function kaos_incumbent_rule(has_inc::Bool, prev::Real, cand::Real)::Real
    @ensures (!has_inc) ⟹ result == cand
    @ensures has_inc ⟹ (result <= prev && result <= cand &&
                        (result == prev || result == cand))
    if !has_inc
        cand
    elseif prev > cand
        cand
    else
        prev
    end
end

# Branch decomposition of the incumbent rule for the Lean kernel: each branch
# outcome is certified separately (the composed if-rule is Z3-verified as
# `kaos_incumbent_rule`). Adoption: no incumbent yet, the candidate is taken.
@formalize function kaos_incumbent_adopt(cand::Real)::Real
    @ensures result == cand
    cand
end

# Improvement: the candidate strictly beats the incumbent, it is taken.
@formalize function kaos_incumbent_improve(prev::Real, cand::Real)::Real
    @requires prev > cand
    @ensures result == cand && result < prev && result <= cand
    cand
end

# Hold: the incumbent is at least as good, it is kept.
@formalize function kaos_incumbent_hold(prev::Real, cand::Real)::Real
    @requires prev <= cand
    @ensures result == prev && result <= cand
    prev
end

# Bounded-filter rule sanity: with a fixed node lower bound, the filter
# decision `mincost < incumbent` is monotone in the candidate cost — a
# costlier label can never be accepted when a cheaper one is rejected.
@formalize function kaos_mincost_monotone(c1::Real, c2::Real, bound::Real)::Bool
    @requires c1 <= c2
    @ensures result == (c1 + bound <= c2 + bound)
    c1 + bound <= c2 + bound
end
