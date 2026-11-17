# Ledgerline ingest pipeline: design note (draft 3)

Eight components. For each, the note says how values are combined and what the team plans to do on that basis.

1. **enrich.** Event fields may be absent. `enrich(f)` applies `f` to a field that is present and leaves an absent field absent. Plan: fuse consecutive calls, replacing `enrich(g)` after `enrich(f)` with a single `enrich(g ∘ f)`, and delete `enrich(identity)` calls.

2. **watermark.** Each partition reports a non-negative integer high-water mark. Marks are combined with `max`, starting from 0. Plan: fold marks in parallel shards, grouping them in whatever way the scheduler chooses.

3. **drift.** Clock readings are non-negative integers. Two readings are combined into their absolute difference `|a − b|`, with 0 used as the neutral reading. Plan: treat this as a monoid and fold readings across shards in parallel, in any grouping.

4. **attempts.** Every step returns a pair `(value, attempts)`. `pure(v)` is `(v, 1)`, because producing a value counts as one attempt. Chaining a step onto a pair runs the step on the value and adds the two attempt counts. The team calls this the Attempt monad. Plan: refactor freely with the monad laws, for example replacing `pure(v) >>= f` with `f(v)`.

5. **overlay.** A configuration setting is optional. Combining two layers takes the later layer's setting if it is present, otherwise the earlier one; "absent" is the neutral layer. Plan: fold layers in any grouping, keeping their order.

6. **transformBatch.** `transformBatch(f)` applies `f` to every event in a batch and returns the batch newest-first (that is, in reversed order) for the convenience of the downstream reader. The team treats it as the batch functor. Plan: fuse `transformBatch(g)` after `transformBatch(f)` into a single `transformBatch(g ∘ f)`.

7. **backpressure.** Scores are integers from 0 to 10. Two scores are combined by addition capped at 10, with 0 as the neutral score. Plan: fold scores in parallel shards, in any grouping.

8. **quota.** Remaining quota is a non-negative integer. Quota values are combined by truncated subtraction (`a ∸ b`, never below 0), with 0 as the neutral value. Plan: treat this as a monoid and fold release events in any grouping.
