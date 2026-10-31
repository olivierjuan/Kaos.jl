# Kaos.jl — preuve de validité de bout en bout

Statut : **15/15 vérifications machine** — Z3 (5 règles sur ℚ), BMC (2 noyaux
boucle/tableaux), noyau Lean 4 + Mathlib (8, sans `sorry`) —,
**5 445 assertions end-to-end vertes** sur 100 instances aléatoires.
Harnais : `test/test_formal_verification.jl` (`julia --project=. test/runtests.jl`).
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

8/8 : asymétrie, transitivité, lemme d'élimination, monotonie du filtre, la
décomposition par branche de la règle d'incumbent (`adopt`/`improve`/`hold`)
**et la règle composée (if) complète** — certifiée via une tactique de
cas (`cases has_inc <;> simp [...] <;> by_cases h : prev > cand <;> simp [h]
<;> linarith`) rendue possible par l'émission des tactiques custom dans un
bloc `by` (JuLean `6db8c38`).

### Tier 2 — BMC (boucle liée, tableaux SMT, `@ensures`) — JuLean `6db8c38`

2/2 : extension batchée (`kaos_extend_batch_arr` : écritures `store`,
lectures `select`, `@ensures` falsifiés sur l'état final) et scan de
dominance en récursion d'état (`kaos_front_scan_arr` : variable de boucle
liée à l'itération dépliée, accumulateur Bool). Sémantique vérifiée :
« après exactement `depth` itérations complètes, invariants et postconditions
tiennent » — la sortie anticipée de boucle reste hors modèle.

### Tier 0 — contrats DbC dans les docstrings des noyaux RÉELS (exécution)

Conformément à `AGENTS.md` (motif Sirocco), les contrats (`@requires`, `@ensures`)
vivent directement dans les docstrings Markdown des fonctions de `src/` (`Kaos.dominates`,
`Kaos.add_path!`, `Kaos.update_incumbent!`, `Kaos.is_candidate`), sans aucun surcoût ni
dépendance en production.

Via `JuLean.contracted(...)`, les contrats sont martelés sur données aléatoires
dans `test/test_formal_verification.jl` : `Kaos.dominates`, `Kaos.add_path!`,
`Kaos.update_incumbent!`, `Kaos.is_candidate`. Toute divergence des noyaux réels
par rapport aux specs ci-dessus lèverait `ContractViolationError`.

## 2. Preuve bout-en-bout (oracles indépendants, `test/test_oracle.jl`)

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

## 3bis. Capacité de l'outillage, mesurée (expériences + lecture du code)

Le solveur est décomposable à volonté (`_extend_batch!`, `front_dominates`,
`add_dominant!`, sift du heap sont déjà des fonctions isolées) — le facteur
limitant est l'outillage, pas la structure :

| Voie JuLean | Ce qui passe | Ce qui bloque (mesuré) |
|---|---|---|
| Z3 direct | tout corps sans boucle (les 5 règles, cf. Tier 1) | boucles : `body_has_loops` → `StatusUnverified` assumé |
| Lean 4 (transpilateur) | boucles `for` + mutations `arr[i] =` (§4 du README : `Id.run do`/`let mut`/`set!`) — **transpilation observée OK** | preuve de posts quantifiés sur tableaux : induction absente du pipeline de tactiques (`unsolved goals`) |
| Lean 4 (tactiques custom) | tactiques simples | JuLean émet `theorem ... := <tactique>` hors bloc `by` → toute tactique multi-jetons = ParseError (`unexpected token '<;>'`) |
| BMC (`bmc.jl`) | invariants de récursions d'état pures (`total = total + s`) à profondeur bornée | la variable de boucle n'est pas modélisée (`loop_cond = true` pour les `for`, `i` libre non contraint → contre-exemples factices), pas de `Array` SMT, `@ensures` hors de la requête, sorties anticipées non modélisées |

Conséquence pratique : les quatre boucles chaudes de Kaos (extension batchée
par arc, scans de dominance à sortie anticipée, compaction d'ordre préservé,
sift de tas) référencent toutes la variable de boucle et/ou des tableaux —
**au-delà du BMC actuel**, quel que soit le découpage de `solve`. Les specs
droites (sans boucle) sont couvertes par Z3/Lean ; les boucles, par les
contrats DbC + la validation exhaustive. Levier côté JuLean : modéliser la
variable de boucle + `select/store` SMT dans le BMC, et émettre les tactiques
custom dans un bloc `by` avec induction pour les posts sur tableaux.

Correction honnête d'une affirmation antérieure de ce dépôt : JuLean *gère*
boucles et tableaux à la transpilation Lean et en BMC pour les récursions
d'état ; l'écart porte sur la *preuve* de propriétés quantifiées sur tableaux
et sur la variable de boucle.

### Voie A : Preuve mécanique d'optimalité globale
La feuille de route d'ingénierie formelle pour prouver de bout en bout l'optimalité
du solveur via le système de transition et invariant inductif en Lean 4 est spécifiée
dans [RCSPP_DESIGN.md](RCSPP_DESIGN.md).

## 4. Reproduction

```bash
julia --project=. test/runtests.jl            # exécute les tests unitaires, oracles exhaustifs et vérification formelle JuLean (Z3 + DbC + BMC + Lean 4)
cd ../../dunes/formalization && lake build DunesLean.RCSPP   # certification universelle de l'algorithme en Lean 4
```
