# Review of "Ledgerline ingest pipeline: design note (draft 3)"

Four of the eight plans are safe as written (1 enrich, 2 watermark, 5 overlay, 7 backpressure) and four are not (3 drift, 4 attempts, 6 transformBatch, 8 quota).
Each unsafe one changes results silently rather than failing, and each has a small repair, given below.

| # | Component | Note treats it as | Structure it really has | Plan safe? |
|---|---|---|---|---|
| 1 | enrich | (functor, implicitly) | **Functor** (the optional-value functor) | **Yes** |
| 2 | watermark | (monoid, implicitly) | **Monoid** (ℕ, max, 0), also commutative | **Yes** |
| 3 | drift | monoid | **None**: not associative | **No** |
| 4 | attempts | monad | **Not a monad**: both unit laws fail; only a functor | **No** |
| 5 | overlay | (monoid, implicitly) | **Monoid** ("last present wins"), not commutative | **Yes**, order must be kept |
| 6 | transformBatch | functor | **None**: both functor laws fail | **No** |
| 7 | backpressure | (monoid, implicitly) | **Monoid** ({0..10}, capped +, 0), also commutative | **Yes** |
| 8 | quota | monoid | **None**: no left unit, not associative | **No** |

All of these verdicts are machine-checked; see "How this was checked" at the end.

## 1. enrich — functor; plan is safe

`enrich` is the map of the optional-value (Maybe/Option) functor. Both laws hold:

- `enrich(identity)` returns its input unchanged, so deleting those calls is safe.
- `enrich(g)` after `enrich(f)` equals `enrich(g ∘ f)`, so fusion is safe.

Two conditions on the implementation, neither of which the note states:

- **"Absent" must be distinct from anything `f` can return.** If absence is represented as `null` and `f` can itself return `null`, the unfused pipeline skips `g` while the fused one calls `g(null)`. With a real option type this cannot happen.
- **`f` and `g` should not depend on effects running between the two passes.** Fusion keeps the per-field order (f then g) but removes the gap between passes.

## 2. watermark — monoid; plan is safe

(ℕ, max, 0) is a monoid: `max` is associative and 0 is a two-sided unit. Folding shards in any grouping gives the same answer.

- It is also commutative and idempotent, so the scheduler may reorder shards and re-deliver a mark without changing the result. That is more freedom than the plan asks for.
- **0 is the unit only because marks are non-negative.** If a mark can ever be negative (a sentinel such as −1 for "no data"), `max(0, −1) = 0 ≠ −1` and the empty-shard value becomes wrong.

## 3. drift — not a monoid; plan is unsafe

`|a − b|` with 0 passes the two checks people usually try: 0 is a two-sided unit and the operation is commutative. It fails the one that parallel folding needs: **it is not associative.**

- Counterexample: readings 1, 2, 3. `| |1 − 2| − 3 | = 2`, but `| 1 − |2 − 3| | = 0`.
- So the folded "drift" depends on how the scheduler groups shards, and two runs over the same readings can disagree.
- Even a sequential fold has no clear meaning: it is not the spread of the readings.

Repair: fold a summary that is a monoid and compute the difference once at the end.

- If "drift" means the spread of readings, fold `(min, max)` pairs (unit: "no readings") and report `max − min`. This is associative and commutative, so any grouping and order work.
- If it means something else (for example difference from a reference clock), that is a per-reading map followed by a `max` or sum, which is again a monoid.

## 4. attempts — not a monad; plan is unsafe

The pair `(value, attempts)` with additive chaining is the Writer construction over (ℕ, +). Writer is a monad only when `pure` attaches the monoid's unit, which is 0. Here `pure(v) = (v, 1)`, so:

- **Left identity fails:** `pure(v) >>= f` has one more attempt than `f(v)`.
- **Right identity fails:** `m >>= pure` has one more attempt than `m`.
- Both fail for every input, not only in corner cases. Associativity of `>>=` does hold.

Consequence for the plan: the example rewrite `pure(v) >>= f` → `f(v)` lowers the attempt count by one each time it is applied. If `f(v) = (v, 3)`, the code reports 4 attempts before the refactor and 3 after. Any retry budget, metric or alert based on the count shifts.

What remains lawful: mapping over the value while leaving the count alone is a functor, and re-association of chains is safe. Only rewrites that add or remove a `pure` are unsafe.

Repair: make `pure(v) = (v, 0)` and add a separate operation, say `attempt(v) = (v, 1)`, used where a real attempt happens. That is the Writer monad over (ℕ, +, 0); all three laws then hold and the planned refactors become safe.

## 5. overlay — monoid; plan is safe as stated

"Later layer wins if present, otherwise the earlier one", with "absent" as unit, is the Last monoid on optional values: associative, with absent as a two-sided unit. Folding layers in any grouping while keeping their order is safe.

- **It is not commutative.** `overlay(present 1, present 2)` is 2; swapped it is 1. The plan's "keeping their order" clause is load-bearing: shards must be contiguous runs of layers and must be combined in layer order, not completion order.
- As in component 1, "present" must be distinguishable from a present-but-empty value (an explicit `null` or `""` meant to override an earlier layer).

## 6. transformBatch — not a functor; plan is unsafe

`transformBatch(f)` is "map `f`, then reverse". The reversal breaks both functor laws:

- **Identity fails:** `transformBatch(identity)` reverses the batch instead of leaving it alone.
- **Composition fails:** two stages reverse twice, restoring the original order; the fused stage reverses once.
  With `f = g = +1` on `[1, 2, 3]`: two stages give `[3, 4, 5]`, the fused stage gives `[5, 4, 3]`.

So the planned fusion flips the order the downstream reader sees, for every batch that is not a palindrome. The values are right and the order is wrong, which is easy to miss in tests that compare sets or single-event batches.

What is true (proved for all `f`, `g` and batches):

- `transformBatch(g)` after `transformBatch(f)` equals the **plain** `map(g ∘ f)`, with no reversal.
- `transformBatch(f)` equals `reverse` after `map(f)`, and also `map(f)` after `reverse`.

Repair: split the component into `mapBatch(f)` (the list functor, lawful, fuse freely) and a single `newestFirst` step at the boundary with the reader. If the split is not possible, the correct fusion rule is "a chain of n stages equals one `map` of the composition, followed by a reversal only when n is odd".

## 7. backpressure — monoid; plan is safe

Addition capped at 10 on {0, …, 10} with unit 0 is a monoid. It is closed on the range, associative, has 0 as a two-sided unit, and is commutative. The capped fold in any grouping equals `min(10, exact sum)`, so parallel shards in any grouping, and in any order, are safe.

Conditions that keep it a monoid:

- **Every input must be in 0..10.** If negative adjustments are ever allowed, associativity fails: with 7, 5, −1, `(7 ⊕ 5) ⊕ −1 = 9` but `7 ⊕ (5 ⊕ −1) = 10`.
- Every shard must use the same cap.

## 8. quota — not a monoid; plan is unsafe

Truncated subtraction with 0 fails two of the three monoid requirements:

- **0 is only a right unit:** `a ∸ 0 = a`, but `0 ∸ a = 0`, which is not `a` unless `a = 0`.
- **Not associative:** `(5 ∸ 3) ∸ 2 = 0`, but `5 ∸ (3 ∸ 2) = 4`.
- It is not commutative either.

So the result of folding release events depends on the grouping, and an empty shard (contributing 0 on the left) wipes out whatever is combined after it.

The underlying confusion is that two different kinds of value are being put in one fold: the remaining quota and the amounts taken from it. The amounts form a monoid; the quota is what that monoid acts on:

- `(q ∸ a) ∸ b = q ∸ (a + b)` for all naturals (proved).

Repair: fold the event **amounts** with (ℕ, +, 0) in any grouping and any order, then apply one truncated subtraction to the starting quota. If the stream also contains events that add quota back, summing is no longer enough because the floor at 0 can bite mid-stream; in that case fold the events as composed functions of the form `q ↦ max(floor, q + delta)`, which are closed under composition and associative, and keep them in order.

## How this was checked

Two files in `/tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armA`:

- `Ledger.agda` type-checks under Agda 2.6.3 with `--safe --without-K`, no postulates or holes. It proves the laws for 1, 2 and 5, the failure of the laws for 3, 4, 6 and 8 (including the universal failure of both unit laws in 4), and the repair facts for 4, 6 and 8.
- `checks.smt2` runs under Z3 4.8.12 and gave the expected answer on every query. It covers 2, 3, 7 and 8, including the full law set for 7 on 0..10 and the out-of-range counterexamples for 2 and 7.

Not checked by machine: the `null`-versus-absent and side-effect caveats in 1 and 5, which depend on the implementation language and were not in the note. The models assume the functions passed to `enrich`, `transformBatch` and `>>=` are pure and total.
