# Review of the Ledgerline ingest design note (draft 3)

Four of the eight plans are safe as written (1 enrich, 2 watermark, 5 overlay, 7 backpressure) and four are not (3 drift, 4 attempts, 6 transformBatch, 8 quota). In each unsafe case the component does not have the structure the note assumes, and the planned change alters results.

This review covers the components as the note describes them. I have not seen the code, so each verdict holds only as far as the code matches the note.

## Verdicts

| # | Component | Structure it really has | Planned change | Verdict |
|---|---|---|---|---|
| 1 | enrich | Functor (the "optional value" functor) | Fuse consecutive calls; delete `enrich(identity)` | Safe, on two conditions (below) |
| 2 | watermark | Monoid (also commutative and idempotent) | Parallel fold, any grouping | Safe |
| 3 | drift | None: not associative, so not a monoid | Parallel fold, any grouping | Unsafe |
| 4 | attempts | Functor only: not a monad | Refactor with the monad laws | Unsafe |
| 5 | overlay | Monoid (not commutative) | Fold in any grouping, order kept | Safe, if order really is kept |
| 6 | transformBatch | None: not a functor | Fuse consecutive calls | Unsafe |
| 7 | backpressure | Monoid (also commutative) | Parallel fold, any grouping | Safe |
| 8 | quota | None: not a monoid | Fold in any grouping | Unsafe |

Every law and every counterexample quoted below was proved in Agda unless I say otherwise; the last section says exactly what that covers.

## What a parallel fold needs

Three different freedoms need three different properties, and the components differ in which they have.

| Scheduler freedom | Property needed | Components that have it |
|---|---|---|
| Any grouping of contiguous shards, combined in the original order (empty shards included) | Monoid: associative, with a two-sided identity | 2, 5, 7 |
| Shards combined in any order | Commutative as well | 2, 7 |
| The same value delivered more than once | Idempotent as well | 2 |

## The eight components

### 1. enrich: functor; the plan is safe on two conditions

`enrich` satisfies both functor laws: `enrich(identity)` changes nothing, and `enrich(g)` after `enrich(f)` equals `enrich(g ∘ f)`. Both planned rewrites are therefore correct.

The conditions:

- **`f` must not be able to produce "absent" itself.** If "absent" is an ordinary value such as `null` that `f` can return, fusion is wrong. The two-call form skips `g` when `f` returns absent; the fused form calls `g` on it. With `f` = "drop the field" and `g` = "default to 0", two calls give absent and the fused call gives 0.
- **`f` and `g` must be free of side effects and exceptions.** This is not checked. Fusion changes how their effects interleave across fields.

### 2. watermark: commutative idempotent monoid; the plan is safe

`max` on non-negative integers is associative and commutative, 0 is a two-sided identity, and `max(a, a) = a`. The scheduler may group shards any way it likes, combine them in any order, and even deliver a mark twice.

0 is the identity only because marks are non-negative. If a mark can ever be negative, the starting value must change.

### 3. drift: no structure; the plan is unsafe

`|a − b|` is commutative and 0 really is neutral, but it is not associative: `||1 − 2| − 3| = 2` while `|1 − |2 − 3|| = 0`. It is not a monoid.

For the plan, with readings 1, 2, 3:

- the sequential fold from 0 gives 2;
- shards `[1]` and `[2, 3]`, folded separately and combined, give 0.

The result depends on the scheduler's grouping. Do not parallelise this fold.

Even the sequential fold depends on the order of the readings, so the team should first decide what quantity it wants. If it is the spread of the readings (largest minus smallest), fold `max` and `min` separately and subtract once at the end. `max` is the monoid from component 2; `min` needs "no reading yet" as its starting value. I have not machine-checked this suggestion.

### 4. attempts: a functor but not a monad; the plan is unsafe

With `pure(v) = (v, 1)`, two of the three monad laws fail, for every input:

| Law | Holds? | Why |
|---|---|---|
| Left identity: `pure(v) >>= f` equals `f(v)` | Never | The left side has one more attempt than `f(v)` |
| Right identity: `m >>= pure` equals `m` | Never | The left side has one more attempt than `m` |
| Associativity of `>>=` | Always | Addition of counts is associative |

The rewrite the note gives as its example, `pure(v) >>= f` to `f(v)`, lowers the attempt count by one every time it is applied. For a step that returns `(v + 1, 1)`, `pure(7) >>= step` is `(8, 2)` and `step(7)` is `(8, 1)`.

What is safe today:

- Re-nesting a chain of `>>=` calls, which uses only associativity.
- Mapping a function over the value while leaving the count alone. That map satisfies the functor laws. A map built from `>>=` and `pure` does not, because it adds an attempt.

To get a real monad, make `pure(v) = (v, 0)` and record an attempt with a separate explicit operation that returns `(v, 1)`. With that unit both identity laws hold, and the planned refactoring becomes sound. This changes the counts existing code reports wherever it calls `pure`, so it is a behaviour change to decide on, not a refactoring.

### 5. overlay: monoid, not commutative; the plan is safe if order is kept

"Later setting wins if present" is associative and "absent" is a two-sided identity. Folding layers in any grouping gives the same result as folding them one by one.

It is not commutative: overlaying 1 then 2 gives 2, and 2 then 1 gives 1. The plan's phrase "keeping their order" is therefore a hard requirement on the scheduler. Shards must be contiguous runs of layers, and shard results must be combined in layer order, not in completion order.

### 6. transformBatch: not a functor; the plan is unsafe

Both functor laws fail.

- **Identity:** `transformBatch(identity)` reverses the batch.
- **Composition:** on the batch `[1, 2]` with `f` and `g` both "add 1", two calls give `[3, 4]` and the fused call gives `[4, 3]`.

Two reversals cancel, so two consecutive calls compute a plain `map(g ∘ f)` in the original order. The planned fusion hands the downstream reader the batch in the opposite order from today.

The correct rule is: `transformBatch(g)` after `transformBatch(f)` equals `transformBatch(g ∘ f)` followed by one more reversal. A chain of k calls equals one map followed by k reversals.

I recommend splitting the component into a plain per-event map, which is a functor and fuses freely, and one explicit reversal at the hand-off to the downstream reader.

I read "newest-first (that is, in reversed order)" literally, as reversal. If the code instead sorts by timestamp, the fusion may be valid, but the identity law still fails. I did not check that reading.

### 7. backpressure: commutative monoid; the plan is safe

Addition capped at 10 on scores 0 to 10 is associative and commutative, 0 is a two-sided identity, and the result stays in 0 to 10. Any grouping and any order give the same total.

Two limits:

- **Scores must stay in 0 to 10.** If a negative score can enter, associativity fails: with −2, 10, 1 the two groupings give 9 and 8 (Z3 model, checked by hand).
- **It is not idempotent.** A score delivered twice counts twice (3 and 3 make 6). Unlike watermark, each score must be folded exactly once.

### 8. quota: not a monoid; the plan is unsafe

Truncated subtraction fails every monoid law except one:

| Property | Holds? | Evidence |
|---|---|---|
| `a ∸ 0 = a` | Yes | |
| `0 ∸ a = a` | No | `0 ∸ a` is 0 for every positive `a` |
| Associative | No | `(5 ∸ 3) ∸ 1 = 1`, `5 ∸ (3 ∸ 1) = 3` |
| Commutative | No | `5 ∸ 3 = 2`, `3 ∸ 5 = 0` |

Folding the events 5, 3, 1 gives 1 or 3 depending on grouping. A left fold seeded with the "neutral" 0 gives 0 for every input.

What does hold is that successive deductions equal one deduction of the sum: `(q ∸ a) ∸ b = q ∸ (a + b)`. So deducting a list of amounts one by one from a starting quota `q` equals `q ∸ (sum of the amounts)`. The safe design is to sum the amounts in parallel (addition is a commutative monoid, so any grouping and any order work) and subtract once from the starting quota.

That holds for a stream of deductions only. The note does not say whether the same stream also carries top-ups. If it does, the floor at 0 makes order matter: from 0, "add 5 then deduct 3" leaves 2 and "deduct 3 then add 5" leaves 5. That example is hand arithmetic, not machine-checked.

## What was checked, and how far to trust it

Grades used: VERIFIED means Agda's type checker accepted a proof of the stated law. ARGUED means a written argument with no machine check.

```
STATUS: VERIFIED for the formal statements; the match between model and code is unchecked

  1 enrich          functor laws (identity, fusion) ................ VERIFIED
                    fusion fails when f can return "absent" ........ VERIFIED (counterexample)
  2 watermark       assoc, comm, identity both sides, idempotent ... VERIFIED
  3 drift           identity, comm ................................. VERIFIED
                    associativity ................................. REFUTED (1, 2, 3; Agda and Z3)
                    max/min repair ................................ SKETCHED, not checked
  4 attempts        left identity, right identity .................. REFUTED for every input
                    associativity of bind .......................... VERIFIED
                    value-only map is a functor .................... VERIFIED
                    pure(v) = (v, 0): both identity laws ........... VERIFIED
  5 overlay         assoc, identity both sides ..................... VERIFIED
                    commutativity ................................. REFUTED
  6 transformBatch  identity law, fusion law ....................... REFUTED
                    two calls = map(g ∘ f); corrected fusion rule .. VERIFIED
                    "sort by timestamp" reading .................... not checked
  7 backpressure    assoc, comm, identity, closure on 0..10 ........ VERIFIED
                    not idempotent; fails with negative scores ..... hand arithmetic / Z3 model
  8 quota           left identity, assoc, comm ..................... REFUTED
                    (q ∸ a) ∸ b = q ∸ (a + b); fold = q ∸ sum ...... VERIFIED
                    mixed top-ups and deductions ................... ARGUED (hand arithmetic)
  Fold theorem      monoid: any contiguous sharding, any bracketing
                    gives the sequential result; commutative: any
                    rearrangement by neighbour swaps ............... VERIFIED
                    instantiated for 2, 5, 7 and the sum in 8 ...... VERIFIED
```

**Agda.** One file, checked with Agda 2.6.3 under `--safe --without-K`, rebuilt from scratch after the last edit, exit code 0. It has no holes and no postulates, and uses only the built-in naturals, equality and lists. A negative control that asserts drift is associative on 1, 2, 3 is rejected, as it should be.

**Z3.** For components 2, 3, 7 and 8, Z3 4.8.12 under the single logic `QF_LIA` returned `unsat` for the negation of every law listed as holding (11 queries) and `sat` with a model for every law listed as failing (5 queries, each model checked by hand). No query returned `unknown`. The `unsat` answers carry no proof certificate, so they corroborate the Agda proofs and are not independent proof.

**Not covered.**

- Whether the code behaves as the note says. The Agda definitions are my reading of the note.
- Whether the functions passed to `enrich` and `transformBatch` are free of side effects and exceptions.
- Machine integer widths. The proofs use unbounded natural numbers. `max` and capped addition cannot overflow; the attempt counter and the sum of quota amounts could.
- That "rearrangement by neighbour swaps" covers every permutation. That is a standard fact I relied on and did not prove.

## Files

- `/tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armE/Ledgerline.agda`: all Agda definitions and proofs, in component order
- `/tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armE/NegativeControl.agda`: the control that Agda is expected to reject
- `/tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armE/laws.smt2`: the Z3 queries
- `/tmp/claude-0/-home-user/fd60e6b2-2faa-55c1-b210-3432d830dba2/scratchpad/exp/armE/agda.out`, `control.out`, `laws.out`: the tool outputs from the final run

To re-run: `LC_ALL=C.UTF-8 agda Ledgerline.agda` and `z3 laws.smt2` in that directory.
