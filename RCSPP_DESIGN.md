# RCSPP Label-Setting Solvers — Preuve de bout en bout (Voie A : Invariant Inductif & Raffinement)

> **Cadre formel :** Lean 4 + Mathlib (toolchain `leanprover/lean4:v4.35.0`), arithmétique rationnelle exacte ($\mathbb{Q}$), extension du socle formel `dunes/formalization` (`DunesLean`).  
> **Cible algorithmique :** `Kaos.NodeSolver` et `Kaos.PathSolver` (`Kaos.jl`), ports stricts de l'OSAK EDF (`rcspp::NodeSolver`, `rcspp::PathSolver`).  
> **Objectif :** Théorème d'optimalité absolue certifié par le noyau Lean 4 sans `sorry` : l'incumbent retourné à convergence est prouvé égal au minimum global sur l'ensemble de tous les chemins réalisables du graphe.

---

## 1. Formulation mathématique & Théorème cible

Soit un graphe orienté fini $G = (V, E)$ avec source $s \in V$ et puits $t \in V$.  
Un chemin $p$ de $s$ à $v$ est une séquence finie d'arcs $e_1, \dots, e_m$ telle que $\operatorname{src}(e_1) = s$, $\operatorname{tgt}(e_m) = v$ et $\operatorname{tgt}(e_i) = \operatorname{src}(e_{i+1})$.

Chaque arc $e \in E$ consomme un vecteur de ressources $\Delta_e \in \mathbb{Q}^K$ avec $\Delta_{e, k} \ge 0$.  
La ressource accumulée d'un chemin $p$ est :
$$R(p) = R_0 + \sum_{e \in p} \Delta_e$$
où la première composante $R(p)_1$ est le coût objectif $\operatorname{cost}(p)$, et les composantes $2 \dots K$ représentent les consommations de ressources soumises à un budget $B \in \mathbb{Q}^{K-1}$.

Un chemin $p$ est **réalisable** si $\forall k \in \{2, \dots, K\}, \; R(p)_k \le B_{k-1}$.  
On note $\mathcal{P}_{\text{feas}}(s, t)$ l'ensemble de tous les chemins réalisables de $s$ à $t$.

### Théorème cible (Théorème d'optimalité globale)

```lean
theorem rcspp_optimal (G : NetworkRCSPP V E) (s t : V) (B : Vector ℚ (K - 1)) :
  match solve G s t B with
  | some (p_opt, c_opt) =>
      IsFeasiblePath G s t p_opt B ∧
      c_opt = pathCost p_opt ∧
      ∀ p, IsFeasiblePath G s t p B → c_opt ≤ pathCost p
  | none =>
      ∀ p, ¬ IsFeasiblePath G s t p B
```

---

## 2. Architecture du système de transition d'état

L'algorithme de label-setting ne peut pas être prouvé d'un seul bloc. Il est modélisé sous la forme d'un **système de transition discret** :
$$\sigma_{k+1} = \operatorname{step}(\sigma_k)$$

```
┌────────────────────────────────────────────────────────────────────────┐
│                        État algorithmique σ                           │
│  - table   : Fin N → Label (labels explorés, arbre de préfixes)        │
│  - heap    : Multiset LabelId (labels actifs en attente d'extension)   │
│  - fronts  : V → List LabelId (labels efficients stationnés par nœud)  │
│  - best    : Option (LabelId × ℚ) (meilleur coût destination courant)  │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                 pop label pi = (u, r) du heap
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                         Extension & Filtrage                          │
│  Pour chaque arc sortant e = (u, v) :                                 │
│  1. Calcul ressource : r' = r + Δ_e                                   │
│  2. Faisabilité budget : r'_k ≤ B_k                                   │
│  3. Filtre A* : r'_1 + h(v) < best.cost                               │
│  4. Test de dominance : ¬ (∃ ℓ ∈ fronts(v), ℓ ≻ r')                   │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                  label candidat r' non dominé
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Mise à jour d'état σ'                          │
│  - Si v = t : best' = update_incumbent(best, r')                      │
│  - Si v ≠ t : fronts'(v) = add_dominant(fronts(v), r')                │
│               heap' = push(heap \ {pi}, r')                            │
└────────────────────────────────────────────────────────────────────────┘
```

### Structures de données Lean 4 (`DunesLean/RCSPP/State.lean`)

```lean
structure Label (V E : Type) [DecidableEq V] [DecidableEq E] (K : ℕ) where
  id     : ℕ
  node   : V
  res    : Vector ℚ K
  parent : Option ℕ
  arc    : Option E

structure RCSPPState (V E : Type) [DecidableEq V] [DecidableEq E] (K : ℕ) where
  labels    : List (Label V E K)
  heap      : List ℕ                    -- indices de labels actifs
  fronts    : V → List ℕ                -- labels efficients par nœud
  incumbent : Option (ℕ × ℚ)            -- (label_id, cost) au puits
```

---

## 3. L'Invariant Inductif Global $\mathcal{I}(\sigma)$

L'invariant $\mathcal{I}(\sigma)$ formalise mathématiquement pourquoi le fait d'élaguer des chemins dominés ne perd jamais le chemin optimal.

$$\mathcal{I}(\sigma) = \mathcal{I}_{\text{sound}}(\sigma) \land \mathcal{I}_{\text{coverage}}(\sigma) \land \mathcal{I}_{\text{pareto}}(\sigma) \land \mathcal{I}_{\text{incumbent}}(\sigma)$$

### 3.1 Validité structurelle ($\mathcal{I}_{\text{sound}}$)
- Tout label $\ell \in \sigma.\text{labels}$ encode un chemin réalisable valide $p(\ell)$ depuis la source $s$ jusqu'à $\ell.\text{node}$.
- La ressource $\ell.\text{res}$ est égale à $R(p(\ell))$.

### 3.2 Couverture d'accessibilité ($\mathcal{I}_{\text{coverage}}$) — **Le cœur de la preuve**
Pour **tout** chemin réalisable $p \in \mathcal{P}_{\text{feas}}(s, v)$ :
Au moins l'une des 3 assertions suivantes est vraie dans l'état $\sigma$ :
1. **Couverture active :** Il existe un préfixe $p_{1..m}$ de $p$ dont le label correspondant est présent dans le $\text{heap}$ ($\exists \ell \in \sigma.\text{heap}, \; p(\ell) = p_{1..m}$).
2. **Couverture par dominance :** Il existe un label $\ell \in \sigma.\text{fronts}(v) \cup \sigma.\text{heap}$ tel que $\ell \succ R(p)$ (la ressource de $\ell$ domine strictement la ressource de $p$).
3. **Élagage par l'incumbent :** Le coût de $p$ dépasse déjà l'incumbent destination courant :
   $$\operatorname{cost}(p) \ge \sigma.\text{incumbent.cost}$$

### 3.3 Optimalité locale de Pareto ($\mathcal{I}_{\text{pareto}}$)
Pour tout nœud $v \in V$, les labels stationnés dans $\sigma.\text{fronts}(v)$ sont deux à deux non dominés :
$$\forall \ell_1, \ell_2 \in \sigma.\text{fronts}(v), \quad \ell_1 \ne \ell_2 \implies \neg (\ell_1 \succ \ell_2)$$

### 3.4 Validité de l'incumbent ($\mathcal{I}_{\text{incumbent}}$)
Si $\sigma.\text{incumbent} = \operatorname{some}(\ell^*, c^*)$, alors :
- $\ell^*.\text{node} = t$ (le label atteint la destination).
- $c^* = \operatorname{cost}(p(\ell^*))$.
- $p(\ell^*)$ est un chemin réalisable de $s$ à $t$.

---

## 4. Lemmes d'étape & Pas inductif

La preuve de préservation de l'invariant se décompose en 4 lemmes modulaires :

```
             ┌──────────────────────────────────────────────────┐
             │       Lemme 1 : Lemme d'élimination additif      │
             │     e ≻ c  ⟹  e + Δ_e ≻ c + Δ_e (DÉJÀ PROUVÉ)   │
             └─────────────────────────┬────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────┴──────────────────────────────────────┐
│                    Lemme 2 : Préservation de la couverture                   │
│  Quand un label pi est retiré du heap, l'extension sur tous ses arcs        │
│  sortants préserve la propriété de couverture pour tous les chemins p.      │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────┴──────────────────────────────────────┐
│                    Lemme 3 : Soundness du filtre de Pareto                   │
│  Si un label candidat c est dominé par un label existant e ∈ fronts(v),     │
│  alors par le Lemme 1, tout prolongement de c est dominé par le             │
│  prolongement de e. Éliminer c ne viole pas I_coverage.                     │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────┴──────────────────────────────────────┐
│                Lemme 4 : Pas inductif global (The Main Step)                │
│            ∀ σ, I(σ) ∧ ¬ terminated(σ) ⟹ I(step(σ))                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Énoncé formel du pas inductif (`DunesLean/RCSPP/Step.lean`)

```lean
theorem rcspp_step_preserves_invariant
    (G : NetworkRCSPP V E) (s t : V) (B : Vector ℚ (K - 1))
    (σ : RCSPPState V E K) (h_inv : RCSPPInvariant G s t B σ)
    (h_not_term : σ.heap ≠ []) :
    RCSPPInvariant G s t B (rcspp_step G s t B σ)
```

---

## 5. Terminaison et Mesure de bien-fondé

Pour conclure la preuve d'un algorithme impératif, Lean exige une **preuve de terminaison**.

### 5.1 Cas DAG (Graphe orienté acyclique — port direct de `topological_order`)
Sur un DAG, chaque nœud $v$ admet un rang topologique $\operatorname{topo}(v) \in \{1, \dots, |V|\}$.  
Puisque chaque arc va d'un rang plus petit vers un rang strictement plus grand, la longueur maximale d'un chemin élémentaire est bornée par $|V|$.  
Le nombre total de chemins possibles est fini. La mesure de terminaison est le nombre de sous-chemins restant à explorer.

### 5.2 Cas général (consommation strictement positive $\Delta_{e, k} \ge \epsilon > 0$)
Puisque les budgets $B_k$ sont finis et que chaque passage par un arc consomme au moins $\epsilon$ d'une ressource :
$$\text{longueur}(p) \le \frac{\max_k B_k}{\epsilon}$$
L'espace des chemins réalisables non dominés est **fini**.  
On construit la fonction de bien-fondé (well-founded relation) sur le cardinal de l'ensemble des chemins admissibles non encore explorés.

```lean
theorem rcspp_terminates
    (G : NetworkRCSPP V E) (s t : V) (B : Vector ℚ (K - 1))
    (h_pos : ∀ e, ∃ k, G.res e k > 0) :
    WellFounded (RCSPPStateTransition G s t B)
```

---

## 6. Déduction de l'optimalité finale

À la terminaison de l'algorithme, $\sigma_{\text{term}}.\text{heap} = \emptyset$.

Par l'invariant de couverture $\mathcal{I}_{\text{coverage}}(\sigma_{\text{term}})$ appliqué à un chemin réalisable arbitraire $p \in \mathcal{P}_{\text{feas}}(s, t)$ :
1. La condition 1 ($\text{heap}$) est impossible car $\text{heap} = \emptyset$.
2. La condition 2 (dominance par un label au puits $t$) implique qu'il existe un label $\ell \in \sigma.\text{fronts}(t)$ qui domine $R(p)$, donc $\operatorname{cost}(\ell) \le \operatorname{cost}(p)$. Comme $\sigma.\text{incumbent}$ est au moins aussi bon que tout label au puits, $\sigma.\text{incumbent.cost} \le \operatorname{cost}(\ell) \le \operatorname{cost}(p)$.
3. La condition 3 donne directement $\sigma.\text{incumbent.cost} \le \operatorname{cost}(p)$.

Dans tous les cas :
$$\forall p \in \mathcal{P}_{\text{feas}}(s, t), \quad \sigma_{\text{term}}.\text{incumbent.cost} \le \operatorname{cost}(p)$$

Ce qui clôt la preuve du théorème principal `rcspp_optimal`.

---

## 7. Raffinement vers l'implémentation Julia (`Kaos.jl`)

Le solveur Julia `Kaos.solve` utilise des optimisations d'ingénierie logicielle avancées :
- Format CSR (`out_start`, `out_arc`, `out_node`)
- Structure-of-Arrays (`Kaos.PathTable`) avec tableau plat de parents
- Heap binaire implicite sur tableau contigu
- Packed SIMD extensions (`_extend_batch!`)

### Théorème de Bisimulation / Raffinement

On établit une relation de raffinement $\sim$ entre l'état Julia $S_{\text{Julia}}$ et l'état Lean $\sigma_{\text{Lean}}$ :
$$S_{\text{Julia}} \sim \sigma_{\text{Lean}}$$

```lean
def Refines (j : KaosJuliaState) (l : RCSPPState V E K) : Prop :=
  j.incumbent_cost = (match l.incumbent with | some (_, c) => c | none => ∞) ∧
  (∀ i ∈ j.heap, ∃ lid ∈ l.heap, j.table.res[i] = (l.labels.get lid).res) ∧
  (∀ v, ∀ lid ∈ j.fronts[v], ∃ lid' ∈ l.fronts v, j.table.res[lid] = (l.labels.get lid').res)
```

Puisque chaque pas de `Kaos.solve` commute avec `rcspp_step` :
$$S_{\text{Julia}} \sim \sigma_{\text{Lean}} \implies \operatorname{step}_{\text{Julia}}(S_{\text{Julia}}) \sim \operatorname{step}_{\text{Lean}}(\sigma_{\text{Lean}})$$

L'optimalité prouvée en Lean 4 est transférée rigoureusement à l'exécution de `Kaos.solve`.

---

## 8. Feuille de route d'implémentation par jalons (Milestones)

L'implémentation de la Voie A s'appuie sur le socle `DunesLean` existant (`/home/D01856/dunes/formalization`) :

| Jalon | Fichier cible | Contenu formel | Statut / Estimation |
|---|---|---|---|
| **M1** | `DunesLean/RCSPP/Basic.lean` | Graphes pondérés multi-ressources, chemins, faisabilité budgétaire, ordre de Pareto strict $\succ$ | **Déjà fait (JuLean Tier 1)** |
| **M2** | `DunesLean/RCSPP/State.lean` | Types d'états `Label`, `RCSPPState`, fonction de transition `rcspp_step` | 150 lignes Lean 4 (2 jours) |
| **M3** | `DunesLean/RCSPP/Lemmas.lean` | Lemme d'élimination de Pareto (`kaos_dominance_additive_extension2`), monotonie A*, clôture de l'incumbent | **Déjà fait (JuLean Tier 3)** |
| **M4** | `DunesLean/RCSPP/Invariant.lean` | Définition de $\mathcal{I}_{\text{coverage}}$ et preuve du pas inductif `rcspp_step_preserves_invariant` | 400 lignes Lean 4 (5 jours) |
| **M5** | `DunesLean/RCSPP/Termination.lean` | Mesure de bien-fondé sur DAG et avec $\epsilon$-consommation | 250 lignes Lean 4 (3 jours) |
| **M6** | `DunesLean/RCSPP/Optimality.lean` | Théorème d'optimalité absolue finale `rcspp_optimal` | 150 lignes Lean 4 (2 jours) |
| **M7** | `Kaos.jl/test/test_refinement.jl` | Test de bisimulation état-par-état entre la trace Julia et la spécification d'état Lean | 100 lignes Julia (1 jour) |

**Total estimé :** ~950 lignes de code Lean 4 nouveau, capitalisant à 100 % sur les 5 théorèmes déjà certifiés dans `ext/kaos_formal_kernels.jl`.
