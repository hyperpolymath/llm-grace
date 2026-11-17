# Ledgerline ingest pipeline, design note draft 3: structure and safety review

## Verdict

Four of the eight plans are safe as written (1, 2, 5, 7), two of them under a condition you need to confirm. The other four (3, 4, 6, 8) would change results. For 4, 6 and 8 there is a machine-checked replacement below; for 3 there is none, because the aggregate is not well defined to begin with.

| # | Component | What it really is | Planned change | Safe? |
|---|---|---|---|---|
| 1 | enrich | Functor | Fuse `enrich(g)` after `enrich(f)`; delete `enrich(identity)` | **Yes**, provided `f` cannot itself return "absent". If it can, fusion is wrong; deletion is still fine. |
| 2 | watermark | Monoid (commutative) | Parallel fold, any grouping | **Yes**, in any grouping and any order. |
| 3 | drift | None. Not a monoid: associativity fails. | Parallel fold, any grouping | **No.** Different groupings give different numbers. |
| 4 | attempts | Functor only. Not a monad: both identity laws fail. | Refactor with the monad laws, e.g. `pure(v) >>= f` to `f(v)` | **No.** That rewrite lowers the attempt count by one at every call site. |
| 5 | overlay | Monoid (not commutative) | Fold in any grouping, keeping order | **Yes**, as long as order really is kept. |
| 6 | transformBatch | None. Not a functor: both functor laws fail. | Fuse two calls into `transformBatch(g ∘ f)` | **No.** The fused call returns the batch in the opposite order to today's two calls. |
| 7 | backpressure | Monoid (commutative) | Parallel fold, any grouping | **Yes**, provided every score entering the fold is already in 0..10. |
| 8 | quota | None. Not a monoid: left identity and associativity fail. | Fold in any grouping | **No.** Different groupings give different balances, and a shard that starts from 0 returns 0. |

Every row of this table is PROVED; the theorem names and files are in the per-component sections.

## What the checks cover

- **Labels.** PROVED means an Agda file that type-checks or a Z3 query whose result is shown. STATED means argued by hand only. ANALOGY means a resemblance with no laws claimed. Anything not PROVED should not be used to justify a code change.
- **Scope.** The proofs are about the operations as the design note describes them, with unbounded non-negative integers and pure, total functions. I have not seen the code. Whether the code matches the note is unverified.
- **"Any grouping" is a theorem, not an inference.** `MonoidFold.agda` proves it for every monoid, and each safe component instantiates it:
  - `any-grouping`: two bracketings of the same values in the same order give the same result, with empty shards allowed. PROVED.
  - `any-grouping-any-order`: for a commutative monoid, the same holds for any rearrangement of the values. PROVED.
  - `foldl-is-fold`: a sequential left fold from the neutral element gives the same result. PROVED.

## The eight components

### 1. enrich: functor

Laws for this component, with "absent" as a separate case of an optional type:

- Identity: `enrich(identity)(x) = x` for every `x`, present or absent. PROVED (`enrich-id`, `C1Enrich.agda`).
- Composition: `enrich(g)(enrich(f)(x)) = enrich(g ∘ f)(x)`. PROVED (`enrich-fuse`).

Both planned changes are safe in that model.

The condition matters if absence is an in-band value (`null`, `None`, `undefined`) and `f` is an ordinary function that may return it for a present input:

- Fusion fails. With `f` returning null and `g` mapping null to a value, the two calls return null and the fused call returns the value. PROVED (`enrichN-fuse-fails`, with `two-calls` and `fused` showing the two results).
- Deleting `enrich(identity)` is still safe. PROVED (`enrichN-id`).
- The fusion that is valid there keeps the null check between `f` and `g`: `enrich(v ↦ enrich(g)(f(v)))`. PROVED (`enrichN-fuse-guarded`).

Not covered: `f` or `g` that throw or have side effects. Unverified.

### 2. watermark: commutative monoid

Laws for `(non-negative integers, max, 0)`:

- Associativity: `max(max(a,b),c) = max(a,max(b,c))`. PROVED (`max-assoc`, `C2Watermark.agda`; Z3 `unsat`).
- Identity: `max(0,a) = a` and `max(a,0) = a`. PROVED (`max-idˡ`, `max-idʳ`; Z3 `unsat`). This relies on marks being non-negative.
- Commutativity: `max(a,b) = max(b,a)`. PROVED (`max-comm`; Z3 `unsat`).

The plan is safe. Any grouping, including empty shards: PROVED (`watermark-any-grouping`). Any grouping of any reordering, so shards may be merged as they finish: PROVED (`watermark-any-grouping-any-order`).

### 3. drift: not a monoid

Laws for `(non-negative integers, |a − b|, 0)`:

- Identity: `|0 − a| = a` and `|a − 0| = a`. PROVED (`diff-idˡ`, `diff-idʳ`, `C3Drift.agda`; Z3 `unsat`).
- Commutativity: `|a − b| = |b − a|`. PROVED (`diff-comm`; Z3 `unsat`).
- Associativity: fails. `||1 − 2| − 3| = 2` but `|1 − |2 − 3|| = 0`. PROVED (`diff-not-assoc`, `left-grouping`, `right-grouping`; Z3 `sat` with its own counterexample 3, 1, 1 giving 1 against 3).

The plan is unsafe: two shardings of the readings 1, 2, 3 report drift 2 and drift 0.

The problem is not only parallelism. A plain sequential fold already depends on the order of the readings: 1, 2, 3 gives 2 and 2, 3, 1 gives 0. PROVED (`order-1-2-3`, `order-2-3-1`). So there is no well-defined aggregate here for a refactoring to preserve. The team needs to decide what number "drift" means before choosing how to compute it.

### 4. attempts: functor only, not a monad

Laws for `pure(v) = (v, 1)` and chaining that adds the counts:

- Left identity, `pure(v) >>= f = f(v)`: fails for every `f` and every `v`. The left side always reports exactly one more attempt. PROVED (`left-identity-never-holds`, `left-count`, `C4Attempts.agda`; Z3 `unsat` on "is there a count m with 1 + m = m").
- Right identity, `m >>= pure = m`: fails for every `m`, again by exactly one. PROVED (`right-identity-never-holds`, `right-count`).
- Associativity, `(m >>= f) >>= g = m >>= (x ↦ f(x) >>= g)`: holds. PROVED (`>>=-assoc`).
- Functor: mapping over the value and leaving the count alone satisfies both functor laws. PROVED (`mapAtt-id`, `mapAtt-∘`). It is not the map you get from `>>=` and `pure`, which adds an attempt. PROVED (`derived-map-differs`).

The cause is that 1 is not the neutral element of addition.

- The named refactoring, `pure(v) >>= f` to `f(v)`, is unsafe. It changes the reported attempt count at every site it touches.
- Any rewrite that adds or removes a `pure` is unsafe for the same reason.
- Rewrites that only re-nest a chain are safe (associativity, PROVED above).

Repair: make `pure(v) = (v, 0)` and add a separately named `attempt(v) = (v, 1)` for the places that mean "this counts as one attempt". With that, all three monad laws hold. PROVED (`left-identity₀`, `right-identity₀`, `assoc₀`). This is a behaviour change: which existing `pure` calls should become `attempt` is a call-site decision I cannot verify from the note.

### 5. overlay: monoid, not commutative

Laws for `(optional setting, later-present-wins, absent)`, writing `earlier ▹ later`:

- Associativity: `(a ▹ b) ▹ c = a ▹ (b ▹ c)`. PROVED (`▹-assoc`, `C5Overlay.agda`).
- Identity: `absent ▹ a = a` and `a ▹ absent = a`. PROVED (`▹-idˡ`, `▹-idʳ`).
- Commutativity: fails. `present(1) ▹ present(2)` is `present(2)`; the other way round it is `present(1)`. PROVED (`▹-not-comm`).

The plan is safe as stated: any grouping of the layers in their original order gives the same result. PROVED (`overlay-any-grouping`).

"Keeping their order" is a hard requirement. Each shard must be a contiguous run of layers, and shard results must be merged earlier-before-later, not as they finish.

### 6. transformBatch: not a functor

`transformBatch(f)` is "map `f`, then reverse". Functor laws for this component:

- Identity, `transformBatch(identity)(xs) = xs`: fails. On `[1, 2]` it returns `[2, 1]`. PROVED (`tb-id-fails`, `C6TransformBatch.agda`).
- Composition, `transformBatch(g)(transformBatch(f)(xs)) = transformBatch(g ∘ f)(xs)`: fails. With both functions the identity on `[1, 2]`, two calls return `[1, 2]` and the fused call returns `[2, 1]`. PROVED (`tb-fuse-fails`, `two-calls`, `fused`).

What does hold:

- Two calls equal a plain map with no reversal: `transformBatch(g)(transformBatch(f)(xs)) = map(g ∘ f)(xs)`. PROVED (`tb-tb`).
- The planned fused call is exactly the reverse of what the two calls return today. PROVED (`planned-fusion-is-reversed`).
- Three calls do equal one `transformBatch` of the composite. PROVED (`tb-tb-tb`).
- Plain `map` is a functor, and reversing commutes with it and undoes itself. PROVED (`map-id`, `map-∘`, `map-rev`, `rev-rev`).

The plan is unsafe: the downstream reader would receive every batch in the opposite order.

- To preserve today's behaviour exactly, replace the two calls with a plain `map(g ∘ f)` and no reversal. PROVED equal (`tb-tb`).
- In general, a chain of k calls equals a map of the composite, reversed only when k is odd. PROVED for k = 2 and k = 3; for general k this is STATED (induction from those two cases) and unverified.
- A cleaner design is to split the component into a mapping step, which is a functor and fuses freely, and one explicit "newest first" step at the end.

Note what `tb-tb` says about the current pipeline: after two calls the batch is back in its original order, not reversed. If the reader expects newest-first after two calls, it is not getting it today.

### 7. backpressure: commutative monoid

Laws for `(integers 0..10, min(a + b, 10), 0)`:

- Closure: the result stays in 0..10. PROVED (`_⊕_` is typed on in-range scores in `C7Backpressure.agda`; Z3 `unsat`).
- Associativity: `min(min(a+b,10)+c,10) = min(a+min(b+c,10),10)`. PROVED (`⊕-assoc`, via `cap-assoc`, which holds for all non-negative integers; Z3 `unsat` on integers and on 8-bit unsigned words).
- Identity: `0 ⊕ a = a` and `a ⊕ 0 = a` for `a` in 0..10. PROVED (`⊕-idˡ`, `⊕-idʳ`; Z3 `unsat`).
- Commutativity. PROVED (`⊕-comm`; Z3 `unsat`).

The plan is safe. Any grouping: PROVED (`backpressure-any-grouping`). Any grouping of any reordering: PROVED (`backpressure-any-grouping-any-order`).

The condition: 0 is neutral only for in-range values. An out-of-range 11 combined with 0 becomes 10. PROVED (`out-of-range-breaks-identity`; Z3 `sat` with a = 11). Validate or clamp scores before they enter the fold. Negative scores are outside what was checked.

### 8. quota: not a monoid

Laws for `(non-negative integers, a ∸ b, 0)`:

- Right identity, `a ∸ 0 = a`: holds. PROVED (`∸-idʳ`, `C8Quota.agda`; Z3 `unsat`).
- Left identity, `0 ∸ a = a`: fails. `0 ∸ 1 = 0`. PROVED (`∸-no-idˡ`; Z3 `sat`).
- Associativity: fails. `(5 ∸ 3) ∸ 2 = 0` but `5 ∸ (3 ∸ 2) = 4`. PROVED (`∸-not-assoc`, `left-grouping`, `right-grouping`; Z3 `sat` with its own counterexample 11, 9, 3 giving 0 against 5).
- Commutativity: fails. PROVED (`∸-not-comm`).

The plan is unsafe. Besides the grouping problem, any shard that folds from the "neutral" 0 returns 0 whatever it is given. PROVED (`shard-from-zero`).

What is really there is a balance being debited, not values being combined with each other:

- Debiting by `a` and then by `b` is debiting by `a + b`: `(q ∸ a) ∸ b = q ∸ (a + b)`. PROVED (`∸-action`; Z3 `unsat`).
- Applying a list of debits one by one equals subtracting their total once. PROVED (`sequential-is-one-subtraction`).
- The total is a sum, and `(non-negative integers, +, 0)` is a commutative monoid, so the total can be computed in any grouping and any order. PROVED (`+-monoid`, `debit-total-any-grouping-any-order`).
- End to end: the sequential result equals the starting balance minus the total computed by any sharding plan. PROVED (`quota-via-plan`).

Safe replacement: sum the event amounts in parallel shards, then apply one truncated subtraction to the starting balance.

Not covered: in fixed-width integers the total can overflow where the proof's unbounded integers cannot. Unverified; use a wide or saturating sum.

## Reproducing the checks

All files are in `/tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armC`. Every Agda file uses `--safe`, with no postulates and no holes.

```
cd /tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armC
LC_ALL=C.UTF-8 agda C1Enrich.agda
LC_ALL=C.UTF-8 agda C2Watermark.agda
LC_ALL=C.UTF-8 agda C3Drift.agda
LC_ALL=C.UTF-8 agda C4Attempts.agda
LC_ALL=C.UTF-8 agda C5Overlay.agda
LC_ALL=C.UTF-8 agda C6TransformBatch.agda
LC_ALL=C.UTF-8 agda C7Backpressure.agda
LC_ALL=C.UTF-8 agda C8Quota.agda
z3 checks.smt2
```

Results from a clean run (interface files deleted first):

- Agda: all eight files, plus the shared `Prelude.agda` and `MonoidFold.agda` they import, type-check with exit code 0 and no errors or warnings.
- Z3: 20 queries, each matching its expectation. 16 are `unsat` (no counterexample to a law that should hold) and 4 are `sat` (a counterexample to a law that should fail):

| Query | Result | Model |
|---|---|---|
| 3 drift, associativity | `sat` | a = 3, b = 1, c = 1: 1 against 3 |
| 7 backpressure, 0 neutral for an out-of-range value | `sat` | a = 11 becomes 10 |
| 8 quota, left identity | `sat` | a = 11: `0 ∸ 11 = 0` |
| 8 quota, associativity | `sat` | a = 11, b = 9, c = 3: 0 against 5 |

## Remaining sections of the skill's output format

**I. Categorical signature.** The verdict table and the per-component sections above are this section. No adjunctions or limits are claimed for any component.

**II. Universal property map.** One real item. The sequential fold of a monoid sends the empty list to the neutral element and concatenation to the operation: `fold(xs ++ ys) = fold(xs) ∙ fold(ys)`. PROVED (`fold-++`, `MonoidFold.agda`). This is the fact the grouping theorems rest on. That fold is the only such map sending `[x]` to `x` is STATED: any such map `h` must satisfy `h([]) = ε` and `h(x ∷ xs) = h([x] ++ xs) = x ∙ h(xs)`, which is fold's definition. No verdict depends on the uniqueness part.

**III. Structural duality analysis.** Nothing real to report for this input.

**IV. Homotopical and univalence report.** Nothing real to report for this input.

**V. Cross-domain functorial translation.** Nothing real to report for this input.

**VI. Structural provocations.** Five questions whose answers change the verdicts above:

1. enrich: can `f` return the same value that represents "absent"? If yes, use the guarded fusion.
2. drift: what single number is the drift of a set of readings supposed to be? The current definition gives different answers for different orders, so there is nothing to preserve yet.
3. attempts: should producing a constant count as an attempt? If yes, it needs a name other than `pure`, because nothing called `pure` can add to the count and still satisfy the monad laws.
4. transformBatch: which order does the downstream reader actually want, and does it know that two chained calls currently hand it the original order?
5. quota: is a "release event" a debit or a credit? If releases give quota back, truncated subtraction is the wrong operation, and the debit-total replacement above does not apply.
