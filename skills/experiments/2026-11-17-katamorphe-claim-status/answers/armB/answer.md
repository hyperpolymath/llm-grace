# Ledgerline ingest pipeline, draft 3: structural review

Four components have the structure the note relies on and their plans are safe: **1 enrich, 2 watermark, 5 overlay, 7 backpressure**. Four do not, and their plans would change results: **3 drift, 4 attempts, 6 transformBatch, 8 quota**.

Every law and counterexample below was machine-checked: the arithmetic ones with Z3 4.8.12, the ones over optional values, lists and pairs with Agda 2.6.3. Both files run cleanly, give the results quoted here, and sit beside this answer:

- `/tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armB/laws.smt2`
- `/tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armB/Laws.agda`

## I. The Categorical Signature

| # | Component | Objects and arrows | Structure it really has | Laws | Plan |
|---|---|---|---|---|---|
| 1 | enrich | field types; `enrich(f) : Maybe A → Maybe B` | **Functor** (the Maybe functor, `A + 1`) | identity and composition both hold | **Safe** |
| 2 | watermark | ℕ with `max`, 0 | **Monoid** (commutative and idempotent: a join-semilattice with bottom) | unit, associativity, commutativity, idempotence hold | **Safe** |
| 3 | drift | ℕ with `\|a − b\|`, 0 | **None** (commutative, has a unit, not associative) | associativity fails | **Unsafe** |
| 4 | attempts | `T v = v × ℕ`, `pure`, `>>=` | **None as specified**: not a monad (bind is associative, but `pure` is not a unit) | both identity laws fail, always, by exactly 1 | **Unsafe** |
| 5 | overlay | `Maybe Setting`, later-wins, absent | **Monoid** (the "last present wins" monoid; not commutative) | unit and associativity hold | **Safe** if layer order is kept, as planned |
| 6 | transformBatch | batches; `reverse ∘ map f` | **None**: not a functor (it is the list functor followed by a reversal) | identity and composition both fail | **Unsafe** |
| 7 | backpressure | {0..10} with capped `+`, 0 | **Monoid** (commutative, not idempotent) | closure, unit, associativity, commutativity hold | **Safe** |
| 8 | quota | ℕ with `∸`, 0 | **None**: not a monoid (it is an action of (ℕ, +, 0) on the quota) | left unit, associativity and commutativity fail | **Unsafe** |

Detail per component:

**1. enrich: functor, safe.** `enrich(identity)` is the identity and `enrich(g)` after `enrich(f)` equals `enrich(g ∘ f)`, for absent and present fields alike. Both rewrites in the plan are valid. One condition: `f` must not be able to turn a present field into an absent one. If absence is encoded as null and `f` may return null, the unfused pipeline skips `g` while the fused one calls `g(null)`.

**2. watermark: commutative idempotent monoid, safe.** Any grouping gives the same result. Because `max` is also commutative and idempotent, reordered shards and duplicate reports are harmless too. 0 is the unit only because marks are non-negative.

**3. drift: no structure, unsafe.** 0 is a unit and the operation is commutative, but it is not associative: `||3 − 1| − 1| = 1` while `|3 − |1 − 1|| = 3`. A parallel fold would return a value that depends on how the scheduler happened to group the readings. This is not a monoid and no regrouping argument applies. If "drift" means the spread of the readings, fold `(min, max)` pairs (a monoid once an "empty" element is adjoined, since `min` has no unit in ℕ) and take `max − min` once at the end. If it means something else, see provocation 1.

**4. attempts: not a monad, unsafe.** Bind is associative, so re-nesting chains is fine. But `pure(v) >>= f` returns `f(v)` with one extra attempt, and `m >>= pure` returns `m` with one extra attempt. Neither identity law holds for any input. The example refactoring in the plan, `pure(v) >>= f` to `f(v)`, lowers the reported count by 1 at every site it touches. The repair is the standard Writer monad: `pure(v) = (v, 0)`, plus a separate explicit operation `attempt(v) = (v, 1)` where a real attempt is made. With that change both identity laws hold and the plan becomes safe.

**5. overlay: monoid, safe.** "Later wins if present, absent is neutral" is associative with absent as a two-sided unit, so layers can be grouped freely. It is not commutative, so shard results must be recombined in layer order, which the plan already requires. It only works if "absent" stays distinct from a setting that is present with an empty value.

**6. transformBatch: not a functor, unsafe.** `transformBatch(identity)` reverses the batch, so the identity law fails. Two calls reverse twice, so `transformBatch(g)` after `transformBatch(f)` equals plain `map(g ∘ f)` in the original order, while the fused `transformBatch(g ∘ f)` is newest-first. On `[1, 2]` with `f = g = +1` the current code gives `[3, 4]` and the fused code gives `[4, 3]`. Batches of length 0 or 1 hide the difference, so single-event tests will pass. The repair: make `transformBatch` a plain map (which is a functor and fuses freely) and reverse once, at the boundary to the downstream reader. Reversal commutes with any map, so it can be moved to the end without changing anything else.

**7. backpressure: commutative monoid, safe.** Addition capped at 10 stays in 0..10, has unit 0, and is associative and commutative, so any grouping and any shard order gives the same score. Two limits. It is not idempotent (`5 ⊕ 5 = 10`), so a duplicated score is counted twice. And it depends on scores being non-negative: with a negative adjustment, `(7 ⊕ 5) ⊕ −1 = 9` but `7 ⊕ (5 ⊕ −1) = 10`.

**8. quota: not a monoid, unsafe.** 0 is a unit on the right only (`0 ∸ 1 = 0`, not 1), and the operation is not associative: `(3 ∸ 1) ∸ 1 = 1` while `3 ∸ (1 ∸ 1) = 3`. A fold in arbitrary grouping gives grouping-dependent quota. What does hold is `(q ∸ a) ∸ b = q ∸ (a + b)`: the amounts form the monoid (ℕ, +, 0) and act on the quota. So sum the amounts in parallel, in any grouping, and subtract the total from the quota once. If the stream mixes events that consume quota with events that return it, the clamp at 0 makes order matter (from 0: consume 5 then return 5 gives 5; the other order gives 0). That case still has an order-preserving monoid: summarise a run of events as a pair `(d, l)` meaning `x ↦ max(x + d, l)`, with consume n = `(−n, 0)`, return n = `(n, n)`, "first then second" = `(d₁ + d₂, max(l₁ + d₂, l₂))`, and unit `(0, 0)`.

## II. Universal Property Map

- **Folding in any grouping** is the universal property of the free monoid: a fold is the unique monoid homomorphism from lists into the target. It exists only when the target is a monoid. That is the whole reason 2, 5 and 7 are safe and 3 and 8 are not.
- **1 enrich.** `Maybe A` is the coproduct `A + 1`; `enrich(f)` is `f + id`. Functoriality follows from the coproduct's universal property.
- **2 watermark.** `max` is the coproduct (join) in the order ℕ viewed as a category and 0 is its initial object. The fold is a colimit, and colimits can be assembled in any grouping.
- **5 overlay.** Start from the semigroup "the right-hand value wins" and freely adjoin a unit (the left adjoint of the forgetful functor from monoids to semigroups). The result is exactly `Maybe Setting` with absent as the unit.
- **7 backpressure.** It is the quotient of (ℕ, +, 0) that identifies everything from 10 upward. The capping map is a monoid homomorphism, so capping in every shard and capping once at the end agree.
- **4 attempts.** A monad on `v × M` of this shape corresponds to a monoid on `M`, with `pure` pairing the value with the monoid's unit. The unit of (ℕ, +) is 0. The note's 1 is not a unit, so no monad arises.
- **6 transformBatch.** The list functor is the free-monoid functor and `map` is its action on arrows. `reverse` is a natural transformation from that functor to itself, not part of it.
- **8 quota.** An action of a monoid on a set, which is a functor from the one-object category (ℕ, +, 0) into sets. The foldable thing is the acting monoid, not the set acted on.
- **3 drift.** No limit, colimit or adjunction applies.

## III. Structural Duality Analysis

- **Coproduct against product (1 against 4).** enrich works on `A + 1`, attempts on `A × ℕ`. The first needs no extra data to be a functor. The second needs a monoid on the second factor and inherits its unit, which is where component 4 goes wrong.
- **Combining against acting (8).** The note treats the quota (a state) and the amounts (events) as the same kind of thing. They are dual roles: events combine with each other, and the combined event acts on the state.
- **Join against meet (2 and the repair of 3).** `max` on ℕ has unit 0; the dual `min` has none. That is why the repaired drift needs an explicit "no readings yet" element.
- **Last against first (5).** "Later wins" and "earlier wins" are opposite monoids. Folding the layers in reversed order silently turns one into the other.
- **Covariant against contravariant (6).** `reverse` turns concatenation around: `transformBatch(f)(xs ++ ys) = transformBatch(f)(ys) ++ transformBatch(f)(xs)`. So besides the fusion problem, splitting a batch across workers and concatenating the pieces in the original order is also wrong for the current definition.

## IV. Homotopical & Univalence Report

All eight carriers are plain sets, so there is no higher-dimensional content here: two values are equal in at most one way, and nothing in the note needs path or homotopy reasoning. What equivalence does contribute is this.

- **Structure, and its absence, transports along equivalence.** backpressure is equivalent to ℕ with everything from 10 up identified; overlay to "last present wins"; attempts with `pure(v) = (v, 0)` to the Writer monad. Conversely, no renaming or re-encoding of drift or quota will make them associative. Only changing the operation does.
- **Symmetries each fold is invariant under.** watermark: regrouping, reordering and duplication. backpressure: regrouping and reordering. overlay: regrouping, and repeating a layer in place. drift and quota: none.
- **transformBatch has a parity invariant.** `reverse` is its own inverse, so n consecutive calls equal one map of the composed function followed by a reversal exactly when n is odd. Any correct fusion has to preserve the parity of the number of calls. The planned fusion changes it.

## V. Cross-Domain Functorial Translation

The same eight shapes in a bank back office. The mapping preserves which laws hold, which is why the verdicts carry over. It is an illustration, not an additional result.

| # | Pipeline | Back office | Why the verdict is the same |
|---|---|---|---|
| 1 | enrich | Stamp the form if the envelope contains one | Two stamps in a row equal one combined stamp; an empty envelope stays empty |
| 2 | watermark | Highest cheque number seen | Tellers can compare tallies in any order, and seeing a cheque twice changes nothing |
| 3 | drift | "Difference between the differences" of three tills | The answer depends on which two tills were compared first |
| 4 | attempts | A clerk who "does nothing" but still stamps the receipt counter | Removing that clerk changes the count, so he was not doing nothing |
| 5 | overlay | Sticky notes on a form, the top one wins | You can pre-stack notes in bundles, provided the bundles keep their order |
| 6 | transformBatch | A clerk who hands the stack back upside down | Two clerks in a row return it right way up; one merged clerk returns it upside down |
| 7 | backpressure | A jar that holds at most ten coins | Pour sub-jars together in any order; the jar is full or it holds the total |
| 8 | quota | Withdrawals from an account that cannot go below zero | Total the withdrawal slips in any grouping, then debit once. Subtracting slips from each other means nothing |

## VI. Structural Provocations

1. **drift.** What is the drift of three or more readings supposed to be: the spread (`max − min`), the differences between consecutive readings, or the deviation from a reference clock? Each has a different lawful structure, and the note's operation matches none of them beyond two readings.
2. **attempts.** Is "producing a value" meant to be an observable event? If so it is an effect, not `pure`. Which call sites, dashboards or retry budgets currently depend on the extra 1 that every `pure` adds?
3. **transformBatch.** Who owns the ordering? Today a pipeline with an even number of calls delivers oldest-first and one with an odd number delivers newest-first. Does the downstream reader, or anything else, already depend on that accident?
4. **quota.** Do "release events" consume quota, return it, or both? If both, is per-key event order guaranteed across shards? The clamp at 0 makes the answer depend on it.
5. **Delivery guarantees.** Only watermark is unaffected by inputs that are duplicated or delivered again later, and only watermark and backpressure tolerate reordering. Does the scheduler guarantee exactly-once delivery and contiguous, in-order shards for overlay? And for enrich: can any `f` in use return an absent value?
