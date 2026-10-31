# Kaos.jl — preuve de validité de bout en bout

Statut : **12/12 spécifications machine-vérifiées** (Z3 + noyau Lean 4/Mathlib),
**5 445 assertions end-to-end vertes** sur 100 instances aléatoires.
Harnais : `formal/verify_kernels.jl` (`julia --project=formal formal/verify_kernels.jl`).
Approche Sirocco.jl : tout le code de vérification vit dans `ext/KaosJuLeanExt`
(weak dependency — `src/` inchangé).

## 1. Ce qui est prouvé

### Tier 1 — les règles de décision, vérifiées sur tous les réels (Z3, SMT-LIB ℚ)

| Théorème | Rôle dans l'algorithme |
|---|---|
| `kaos_dominance_asymmetry2` | la dominance stricte de Pareto (`docs/main.dox`) est asymétrique : un label ne peut dominer et être dominé |
| `kaos_dominance_transitivity2` | la dominance est transitive : retirer un label dominé ne perd jamais l'optimum |
| `kaos_dominance_additive_extension2` | **lemme d'élimination** : si e ≻ c, alors e+s ≻ c+s pour toute extension d'arc additive — étendre un candidat dominé ne peut rien produire de meilleur |
| `kaos_incumbent_rule` | la règle d'incumbent (if complet) calcule bien `min{précédent, candidat}` avec sémantique d'adoption |
| `kaos_mincost_monotone` | la décision du filtre A* (`mincost < incumbent`) est monotone en le coût candidat |

### Tier 3 — noyau Lean 4 + Mathlib (certifié par le kernel, sans `sorry`)

7/7 : asymétrie, transitivité, lemme d'élimination, monotonie du filtre, plus la
décomposition par branche de la règle d'incumbent (`adopt`/`improve`/`hold`).
La règle composée (if) reste au niveau Z3 : le transpilateur JuLean écrit les
tactiques hors bloc `by` (limitation outillée, pas mathématique) et le terme
`min`/les postconditions `!`-sur-`Bool` ne sont pas traduisibles symétriquement.

### Tier 0 — contrats DbC sur les noyaux RÉELS (exécution)

64 000 appels contractuels (`@requires`/`@ensures` actifs) martelés sur données
aléatoires : `dbc_dominates` (20 000 paires, N∈2..4), `dbc_add_path!` +
`dbc_update_incumbent!` (24 000 appels), `dbc_is_candidate_bounded` (20 000
triples). Toute divergence des noyaux réels par rapport aux specs ci-dessus
lèverait `ContractViolationError`.

## 2. Preuve bout-en-bout (indépendante de JuLean, `test/test_formal_verification.jl`)

100 instances aléatoires (multigraphes DAG en couches, 2–3 dimensions de
ressource, budgets variés, arcs parallèles) × 4 combinaisons
solveur×filtre :

1. **Optimalité** : l'incumbent retourné égale **exactement** (égalité flottante,
   même ordre d'accumulation) le minimum de l'**énumération exhaustive de
   l'ensemble réalisable complet** — seule preuve couvrant tout l'espace de recherche.
2. **Validité du chemin** : re-marché indépendamment (arcs retournés,
   ressources ré-étendues, chaque préfixe re-vérifié réalisable).
3. **Cas infaisable** : destination inatteignable ⇒ chemin vide, coût `Inf`.
4. **Rétrogradation en SPP** : sans contrainte, l'optimum Kaos égale un
   **Dijkstra indépendant** (implémentation séparée dans le harnais).
5. **Bornes A*** : les bornes `BoundedFilter` égales au DP backward exact
   indépendant (elles sont exactes sur DAG, jamais des sur-estimations).

Résultat : **5 445 / 5 445 assertions passent** (environ 4 s).

## 3. Chaîne de raisonnement couverte

```
règles mathématiques ──Z3 (ℚ, contre-exemple ou unsat)──▶ valides
règles mathématiques ──noyau Lean 4/Mathlib (sans sorry)──▶ valides
noyaux RÉELS Julia ────contrats DbC + martelage aléatoire──▶ conformes aux règles
solveur complet ──────énumération exhaustive + Dijkstra ind.──▶ optimaux, bout en bout
```

## 4. Reproduction

```bash
julia --project=. test/runtests.jl            # inclut la preuve end-to-end
julia --project=formal formal/verify_kernels.jl   # Z3 + DbC + Lean (proj. Mathlib ~/dunes/formalization)
```

`formal/Project.toml` référence JuLean via `[sources]` (chemin relatif
`../../../dunes/JuLean.jl`) — ajuster si l'arborescence diffère.
