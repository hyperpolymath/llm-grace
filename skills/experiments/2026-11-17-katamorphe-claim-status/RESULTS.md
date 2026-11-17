# Katamorphe claim-status test, 2026-11-17

One run per arm, one model, one design note with eight components (four sound plans, four plausible but wrong).
Answer key: seven claims accepted by `agda --safe` (no holes, no postulates); capped addition is Z3 `unsat`, no certificate.
Verdicts and claim counts were extracted by a reader blind to the arm labels; counts depend on that reader's granularity.

| Arm | Instructions | Verdicts correct | Extra structural claims | Tied to a machine check | Asserted only | Per-claim labels | Words |
|---|---|---|---|---|---|---|---|
| A | none | 8/8 | 21 | 7 | 12 | no | 1,597 |
| B | katamorphe as written | 8/8 | 33 | 0 | 24 | no | 2,231 |
| C | katamorphe + stand-in labelling rule | 8/8 | 27 | 23 | 2 | yes | 2,397 |
| D | katamorphe + proof-craft | 8/8 | 45 | 29 | 6 | yes | 2,725 |
| E | proof-craft alone | 8/8 | 26 | 16 | 7 | partly (end ledger) | 2,048 |

Every proof file the arms produced was re-run independently and passes `agda --safe`; the two deliberate negative controls are rejected.

Re-run later under the estate's canonical flags (`--safe --without-K --cubical-compatible`), with Agda 2.6.3 and with the Guix-pinned Agda 2.7.0.1: the answer key passes; 14 of 15 arm files pass; the failure is arm C's capped-addition proof, which uses axiom K. Arms D and E both prove capped addition in files that pass, so that item of the key has kernel-checked witnesses beyond the Z3 result.

Limits: no repeat runs; all arms were told Agda and Z3 were installed, which may have prompted checking; the test did not separate the arms on correctness (ceiling).
