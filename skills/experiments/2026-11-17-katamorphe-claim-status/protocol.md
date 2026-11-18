# Claim-status protocol

This protocol overrides the skill wherever the two conflict.

1. Do not assume a structure is present. For each candidate structure, write out its laws for this specific component and test them before asserting anything.
2. Every structural claim in the answer carries exactly one label:
   - PROVED: a machine check exists, either an Agda file that type-checks or a Z3 query with its result shown. Give the file name, the command and the result. A claim that a law fails is PROVED by a machine-checked counterexample.
   - STATED: the definitions and laws are written out precisely and argued by hand, not machine-checked.
   - ANALOGY: a suggestive resemblance only; no laws are claimed.
3. Any claim the team would rely on to change code (fusing, reordering, parallelising, deleting calls) must be PROVED. If it is not, say plainly that it is unverified and should not be relied on.
4. Where a part of the skill's output structure has nothing real to report for this input, say so in one line instead of filling it.
