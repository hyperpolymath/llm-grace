# Ledgerline ingest pipeline: structure review of design note draft 3

**Bottom line.** Four of the eight plans are safe: 1 enrich, 2 watermark, 5 overlay and 7 backpressure, each under a condition stated below. Four are unsafe: 3 drift, 4 attempts, 6 transformBatch and 8 quota. Each unsafe one has a small counterexample and a repair.

**How to read the grades.** Every structural claim carries one of these tags.

- **VERIFIED**: accepted by the Agda 2.6.3 type checker with `--safe --without-K`, no holes, no postulates. The name in backticks is the lemma in `Ledgerline.agda`.
- **Z3 unsat**: Z3 4.8.12 found no counterexample under logic QF_LIA. No certificate was produced, so this rests on trusting the solver.
- **Z3 model**: a counterexample Z3 found, which I then re-evaluated independently.
- **ARGUED**: a written argument, not machine-checked.
- **SKETCHED**: an idea only; gaps expected.

The first skill asks for every system to be shown as categorical structure. Where the laws fail I report "none" instead, and sections IV and V are deliberately thin: they contain only claims I could grade.

## I. The Categorical Signature

| # | Component | Objects (carrier) | Morphisms (operation) | Structure it really has | Planned change |
|---|---|---|---|---|---|
| 1 | enrich | optional field, `Maybe A` | `enrich(f)` | **Functor** | Safe, if "absent" is a tag outside the field type and steps are pure |
| 2 | watermark | integers ≥ 0 | `max`, unit 0 | **Monoid** (commutative, idempotent) | Safe |
| 3 | drift | integers ≥ 0 | `\|a − b\|`, unit 0 | **None**: not associative | **Unsafe** |
| 4 | attempts | pairs `(value, count)` | `pure`, `>>=` | **Not a monad**: both unit laws fail. Functor with an associative bind | **Unsafe** |
| 5 | overlay | optional setting | later-present-wins, unit absent | **Monoid** (not commutative, idempotent) | Safe as written (order kept) |
| 6 | transformBatch | batches (lists) | reverse ∘ map f | **None**: not a functor | **Unsafe** |
| 7 | backpressure | integers 0..10 | addition capped at 10, unit 0 | **Monoid** (commutative, not idempotent) | Safe, if each score is delivered exactly once |
| 8 | quota | integers ≥ 0 | `a ∸ b`, "unit" 0 | **None**: not a monoid. It is a monoid *action* | **Unsafe** |

**What "fold in any grouping" needs.** For any monoid, every bracketing of the same sequence, with empty shards allowed and each shard started from the unit, equals the sequential left-to-right fold (VERIFIED: `Fold.regroup`, `Fold.grouping-vs-sequential`, `Fold.fold-shards`). If the operation is also commutative, any reordering gives the same result (VERIFIED: `Fold.Commutative.fold-perm`). Components 2, 5 and 7 are instances of these theorems; `Playback.agda` restates them at each component.

### 1. enrich: functor; plan safe under two conditions

Both rewrites hold for every input: `enrich(identity)` does nothing, and `enrich(g)` after `enrich(f)` equals `enrich(g ∘ f)` (VERIFIED: `Enrich.enrich-id`, `Enrich.enrich-fuse`).

- **Condition (a).** "Absent" must be a separate tag, not a value that `f` can return. If absent is a `null` inside the field's own type, fusion is wrong: when `f` returns null and `g` turns null into a default, two calls give absent and the fused call gives the default (VERIFIED on a model: `Enrich.fusion-fails-with-null`).
- **Condition (b).** `f` and `g` are pure and total. The proof says nothing about steps that log, throw or call out; I did not examine those.

### 2. watermark: commutative idempotent monoid; plan safe

Associativity, both unit laws, commutativity and idempotence hold on integers ≥ 0 (VERIFIED: `Watermark.max-assoc`, `max-idˡ`, `max-idʳ`, `max-comm`, `max-idem`; Z3 unsat agrees). The scheduler may group and reorder freely.

- **Condition.** Marks must be non-negative, as the note says. With a −1 "no data" sentinel, 0 stops being neutral: `max(0, −1) = 0` (Z3 model, re-evaluated).

### 3. drift: none; plan unsafe

0 is a two-sided unit and the operation is commutative (VERIFIED: `Drift.dist-idˡ`, `dist-idʳ`, `dist-comm`), but it is not associative: `||1−1|−2| = 2` while `|1−|1−2|| = 0` (VERIFIED: `Drift.not-assoc`). So it is not a monoid.

- **Effect on the plan.** Readings 1, 1, 2 folded sequentially from 0 give 2. Split into shards `[1]` and `[1, 2]` they give 0 (VERIFIED: `Drift.sequential-run`, `sharded-run`).
- **Repair.** If the intended number is the spread (highest minus lowest), which is my guess and needs confirming, fold `(lowest, highest)` pairs with `(min, max)`, use "no reading yet" as the unit, and subtract once at the end. That is a monoid, so any grouping is safe (VERIFIED: `Spread.⊙-assoc`, `⊙-idˡ`, `⊙-idʳ`, `hull-assoc`). Reordering is also safe (ARGUED: `min` and `max` are commutative; only `max` was machine-checked).

### 4. attempts: not a monad; planned rewrite unsafe

- **Left identity fails for every `f` and `v`.** `pure(v) >>= f` always reports one more attempt than `f(v)` (VERIFIED: `Attempts.left-identity-fails`). Example: `pure(7) >>= (v ↦ (v, 5))` is `(7, 6)`, while `f(7)` is `(7, 5)`. The rewrite named in the note silently drops an attempt.
- **Right identity fails for every pair** (VERIFIED: `Attempts.right-identity-fails`).
- **Associativity holds** (VERIFIED: `Attempts.bind-assoc`). Re-nesting a chain of steps is safe; any rewrite that adds or removes a `pure` is not.
- **Functor part.** Mapping the value and leaving the count alone is a functor (VERIFIED: `Attempts.amap-id`, `amap-∘`). A map built from `>>=` and the note's `pure` is not that functor: it adds an attempt (VERIFIED: `derived-map-miscounts`).
- **Repair.** The unit is forced: any `pure(v) = (v, k)` that satisfies left identity has `k = 0` (VERIFIED: `Attempts.unit-forced`). With `pure(v) = (v, 0)` and an explicit `tick` of one attempt for steps that really attempt something, all three laws hold (VERIFIED: `left-identity₀`, `right-identity₀`, `bind-assoc`). This changes reported counts, so it is a behaviour decision, not a refactor.

### 5. overlay: non-commutative monoid; plan safe as written

Associativity, both unit laws and idempotence hold (VERIFIED: `Overlay.◁-assoc`, `◁-idˡ`, `◁-idʳ`, `◁-idem`). It is not commutative: layer 1 then 2 gives 2, layer 2 then 1 gives 1 (VERIFIED: `OverlayOrderMatters.not-comm`). The plan keeps order and only regroups, which is exactly what a non-commutative monoid allows.

- **Condition.** A layer cannot say "unset this setting". If one can, that is a third state and this model no longer applies (not examined).
- **Many settings.** A whole configuration is one such monoid per setting, combined key by key (ARGUED: the laws hold in each key separately; not machine-checked).

### 6. transformBatch: none; fusion unsafe

- **Identity law fails.** `transformBatch(identity)` on `[1, 2, 3]` returns `[3, 2, 1]` (VERIFIED: `TransformBatch.identity-law-fails`).
- **Composition law fails.** With `f = g = (+1)` on `[1, 2, 3]`, two calls return `[3, 4, 5]` and the fused call returns `[5, 4, 3]` (VERIFIED: `TransformBatch.fusion-fails`).
- **What is true.** Two calls equal a plain order-preserving map of `g ∘ f`, because the two reversals cancel (VERIFIED: `two-calls-law`). Three calls equal one `transformBatch(h ∘ g ∘ f)` (VERIFIED: `three-calls-law`). In general the fused result needs a reversal exactly when the number of calls is odd (ARGUED by induction from those two lemmas; not machine-checked for general n).
- **Repair.** Split it into `mapBatch(f)`, which is the list functor and fuses freely (VERIFIED: `map-id`, `map-∘`), and one `newestFirst` reversal at the reader boundary.
- **Ambiguity to resolve.** I formalised "reversed order", as the note says in brackets. If the code instead *sorts* newest-first, the identity law still fails on unsorted batches, and fusion would hold only if `f` and `g` leave the sort key alone (SKETCHED).

### 7. backpressure: commutative monoid on 0..10; plan safe

Associativity, both unit laws, commutativity and closure on 0..10 hold (VERIFIED: `Backpressure.⊕-assoc`, `⊕-idˡ`, `⊕-idʳ`, `⊕-comm`, `min-≤`; Z3 unsat agrees). Grouping and reordering are both safe.

- **Bonus.** Capping early never changes the result: `min(a + b, 10)` equals capping `a` and `b` first and then cap-adding them (VERIFIED: `Backpressure.cap-hom`). Shards may keep exact sums and cap once at the end.
- **Condition (a).** It is not idempotent: `3 ⊕ 3 = 6` (VERIFIED: `duplicate-counts`). A redelivered score is counted twice, unlike watermark.
- **Condition (b).** Scores must stay ≥ 0. If negative adjustments are ever clamped into 0..10, associativity fails: for 8, −1, 0 the two groupings give 7 and 8 (Z3 model, re-evaluated).

### 8. quota: none; plan unsafe

- **0 is only a right unit.** `a ∸ 0 = a`, but `0 ∸ 1 = 0` (VERIFIED: `Quota.left-identity-fails`).
- **Not associative.** `(1 ∸ 1) ∸ 1 = 0` while `1 ∸ (1 ∸ 1) = 1` (VERIFIED: `Quota.not-assoc`).
- **Effect on the plan.** Quota 10 with releases 4 then 3 leaves 3 sequentially. Grouping the two releases first gives `10 ∸ (4 ∸ 3) = 9`, six units too many (VERIFIED: `Quota.sequential-run`, `grouped-run`). Folding from the "neutral" 0 always returns 0 (VERIFIED: `Quota.from-zero`).
- **The real structure.** The amounts form the commutative monoid (integers ≥ 0, +, 0), and they act on the quota: `(q ∸ a) ∸ b = q ∸ (a + b)` (VERIFIED: `Quota.action`).
- **Repair.** Fold the amounts with `+` in any grouping and order, then subtract the total once. That equals the sequential drain (VERIFIED: `Quota.drain`, `Quota.Amounts.fold-perm`).
- **If releases add quota back.** The note does not say. If additions and subtractions mix, the floor at 0 makes order matter: from 0, "−5 then +5" gives 5 and "+5 then −5" gives 0 (hand evaluation). The steps `x ↦ max(x + a, b)` are closed under composition (Z3 unsat, plus a one-line calculation), so they form a non-commutative monoid: safe to regroup, not to reorder (ARGUED).

## II. Universal Property Map

- **Free monoid.** Lists are the free monoid, and `fold` is a monoid homomorphism from lists to the carrier (VERIFIED: `Fold.fold-++`). This one fact carries plans 2, 5 and 7. Uniqueness of that homomorphism is textbook background, not checked here and not used.
- **2 watermark.** `max` is the least upper bound, i.e. the coproduct in the order (integers ≥ 0, ≤), and 0 is the initial object (VERIFIED: `Watermark.max-ub₁`, `max-ub₂`, `max-least`).
- **5 overlay.** It is the "later wins" semigroup with a unit adjoined (VERIFIED: `Spread.OverlayIsAdjoin.same` with `Spread.Adjoin`). That adjoining a unit is left adjoint to forgetting it is background, not checked.
- **7 backpressure.** It is a quotient of (integers ≥ 0, +, 0): capping is a monoid homomorphism onto 0..10 (VERIFIED: `cap-hom`, `min-of-≤`).
- **8 quota.** A monoid action is the same thing as a functor from the one-object category of (integers ≥ 0, +, 0) to sets. The action laws are VERIFIED; the identification is definitional (ARGUED).
- **1 enrich.** `Maybe A` is `A + 1` and `enrich(f)` is `f + id` (ARGUED: read off the two-case definition).
- **3 drift, 4 attempts as specified, 6 transformBatch.** No universal property found; none claimed. The repaired attempts is the writer monad of (integers ≥ 0, +, 0); its three laws are VERIFIED in section I.

## III. Structural Duality Analysis

- **max and min.** The dual of watermark, a low-water mark under `min`, is associative (VERIFIED: `Spread.min-assoc`) but has no unit among the integers ≥ 0 (VERIFIED: `Spread.min-no-unit`). Any "lowest value" fold needs an explicit "no data yet", which is why the drift repair adjoins one.
- **Later wins and earlier wins.** Overlay with its arguments swapped is also a monoid (ARGUED: swap the arguments in each verified law).
- **Monad unit and monoid unit.** For attempts, the monad's unit must carry the monoid's unit, so `pure` must count 0 (VERIFIED: `unit-forced`). I did not examine the comonad side (reading the count) and make no claim about it.
- **Algebra and coalgebra.** `fold` is the list catamorphism. The note describes no unfold or stream structure; none claimed.

## IV. Homotopical & Univalence Report

- **No higher structure.** Every carrier here is a plain set. I claim nothing above that level. The Agda development uses no univalence, no function extensionality and no axiom K; every law is stated pointwise.
- **Equivalent is not equal, 6 transformBatch.** `[3, 4, 5]` and `[5, 4, 3]` are the same bag and different lists. If the downstream reader ignored order, transformBatch would be a functor on bags and fusion would be fine (ARGUED: reversal is a permutation and map commutes with permutations). The note says the order exists for the reader, so it is observable and fusion is unsafe.
- **Equivalent is not equal, 1 enrich.** A tagged optional and a nullable value are not equivalent representations when the field type contains null, so the functor laws do not transfer (VERIFIED on the model in section I).
- **7 backpressure.** Two scores are equal exactly when their numbers are equal; the bound proof carries no information (VERIFIED: `Backpressure.score-≡`).

## V. Cross-Domain Functorial Translation

Target domain: a harbour office. This is a renaming of carriers and operations, so it preserves exactly the laws graded above and adds no evidence.

| Component | Harbour reading | What carries over |
|---|---|---|
| 2 watermark | highest tide line on the wall | repaint lines in any order, the top line is the same |
| 5 overlay | notices pinned over each other, blank sheets transparent | pre-stapling sub-piles is harmless, shuffling the pile is not |
| 7 backpressure | a 10-litre bucket that overflows | pour jugs into a tub first or straight in: same level (`cap-hom`) |
| 8 quota | a tank drained by taps | only the total drawn matters (`action`); subtracting one tap's draw from another's is meaningless |
| 3 drift | the gap between two gaps | not the gap between the original readings |
| 6 transformBatch | a mirror | one mirror flips, two restore; replacing two mirrors by one leaves the image flipped |
| 4 attempts | a turnstile | `pure = 1` counts someone who only stood at the gate |

## VI. Structural Provocations

1. **enrich.** Is "absent" a tag outside the field's type or a null inside it, and can any `f` return it?
2. **Scheduler.** Does it only regroup, or also reorder and redeliver? Watermark tolerates all three. Backpressure tolerates regrouping and reordering, not redelivery. Overlay tolerates regrouping only. (Tolerance of duplicates is ARGUED from idempotence, not machine-checked.)
3. **drift.** What number is drift meant to report? If it is the spread, use the `(lowest, highest)` fold. If it is something else, define it sequentially and do not shard it.
4. **attempts.** Does `pure` attempt anything? If counts feed retry budgets or billing, moving to `pure = (v, 0)` changes the numbers people see.
5. **quota.** Do release events add quota, remove it, or both? The answer decides between "sum then subtract once" and the order-sensitive clamp monoid.

## Epistemic ledger

```
STATUS: the verdict for each of the eight components rests on VERIFIED lemmas
        plus the modelling choices listed below the ledger;
        side remarks carry the weaker grades listed under OWED

Machine register
  Ledgerline.agda ........ VERIFIED (Agda 2.6.3, --safe --without-K, clean rebuild,
                           zero holes, no postulates, no standard library;
                           only builtin pragma: NATURAL, for numerals)
  Playback.agda .......... VERIFIED (generic theorems restated per component)
  NegControl.agda ........ fails to type-check, as intended (2 != 0)
  Z3, logic QF_LIA, default options, 19 queries
    14 unsat ............. no certificate; 13 are duplicated by Agda on naturals,
                           clampshift_compose is solver-only
    5 sat ................ models re-evaluated with shell arithmetic
  Falsification .......... Z3 run before any proof was written

Human register
  OWED  transformBatch, general n-call parity ......... ARGUED
  OWED  overlay across many settings .................. ARGUED
  OWED  duplicate tolerance (watermark, overlay) ...... ARGUED
  OWED  spread fold, reordering ....................... ARGUED
  OWED  clamp-shift monoid for mixed quota events ..... ARGUED + Z3 unsat
  OWED  transformBatch "sort" reading ................. SKETCHED
  Not examined: side effects, exceptions, timing of steps
```

**Modelling choices the team should confirm.** Each is my reading of the note, not something the note states outright.

- Integers are unbounded naturals. `max` and capped addition cannot overflow a fixed width (ARGUED); attempt counts could, and I did not examine that.
- "Grouping" means bracketing consecutive items with order kept and empty shards allowed. Reordering is treated separately.
- "Absent" is a separate tag (see condition (a) of component 1).
- A batch is a finite list and transformBatch reverses it.
- `f`, `g` and pipeline steps are pure, total functions.
- Chaining in attempts adds the two counts with ordinary addition.

**Files** (all in `/tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armD/`):

- `Ledgerline.agda`: all proofs and counterexamples
- `Playback.agda`: grouping and reordering theorems restated per component
- `NegControl.agda`: negative control, expected to fail
- `run_z3.sh`, `z3/*.smt2`, `z3_results.txt`: solver queries and output

To re-check: `LC_ALL=C.UTF-8 agda Ledgerline.agda`, `LC_ALL=C.UTF-8 agda Playback.agda`, `bash run_z3.sh`.
