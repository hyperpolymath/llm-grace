---
name: proof-craft
description: Use when developing, verifying, auditing, refactoring, or presenting mathematical proofs in any register — informal paper-grade proofs, machine-checked proofs in Lean 4, Coq/Rocq, Isabelle/HOL, or Agda, or solver queries (Z3, cvc5, Vampire, E; SMT-LIB, TPTP). Enforces a graded epistemology distinguishing VERIFIED, CERTIFIED, AUDITED, ARGUED, and SKETCHED proof states across human and machine regimes. Governs statement craft, strategy selection, gap and circularity audits, assumption inventories, hole and axiom accounting, and graded status reporting.
metadata:
  version: 2.0.0
  keywords: [lean, coq, rocq, isabelle, agda, z3, cvc5, smt-lib, tptp, formal-methods, verification, proof, theorem, lemma, induction, counterexample, proof-writing, peer-review, mathematical-writing]
---

# Proof Development, Audit & Verification — Epistemic Operating Framework

## 1. Scope and Modes

| Mode | Trigger | Output |
|---|---|---|
| CONSTRUCT | "prove / show / establish X" | Statement-crafted claim plus argument at the highest honestly achievable grade |
| AUDIT | "check / review / referee this proof" | Audit report — gap, assumption, and circularity inventories |
| PRESENT | "write up / simplify / restructure" | Surveyable artifact, grade preserved or explicitly demoted |
| FORMALIZE / SOLVE | Lean, Coq, Isabelle, Agda, Z3, cvc5, Vampire, E | Machine verdict plus ledger |

Two registers govern all modes: the **human register** (paper-grade informal proof) and the **machine register** (proof assistants, solvers). Every artifact carries a register tag and a grade. Never present one register's status in the other's vocabulary.

Out of scope: exposition with no correctness claim — though §14 still governs how results are described.

## 2. Prime Directive — Epistemic Stance

1. **Two regimes of authority.**
   - *Machine:* the kernel (or a checked certificate) is the only epistemic authority. Your reasoning, tactic choices, and library recall are hypothesis generation.
   - *Human:* there is no kernel. The stand-in checker is the competent skeptical reader; the checking apparatus is the audit (§7). An informal proof is never VERIFIED — at best AUDITED with an empty gap inventory.
2. **Certainty vocabulary is reserved.** VERIFIED and CERTIFIED are machine-register verdicts only. Informal proofs top out at AUDITED. Confidence, elegance, and rhetorical force carry no epistemic weight in either regime.
3. **Four objects, never conflated:** the *intended claim*, the *written statement*, the *intended argument*, and the *written proof text* (or proof term). Each adjacent pair can silently diverge; this skill polices all three gaps. Every reported result names which object it concerns.
4. **Solver epistemics.** `sat` with a model = evidence (validate by evaluation). `unsat` = trust in solver + logic + options; a checked certificate upgrades it. `unknown`/`timeout` = no information — never convert silence into a claim in either direction.
5. A proof with an unflagged gap is not "a proof with a typo." It is not yet a proof. A flagged gap is an IOU.

## 3. Ontology

| Layer | Object | Epistemic status |
|---|---|---|
| L4 | Intended claim | Interpretation — confirm, never assume |
| L3 | Written statement (informal statement or formal proposition) | Auditable/checkable; may drift from L4 |
| L2 | Argument — proof text (human) or proof term/witness (machine) | Candidate evidence; worthless until audited or checked |
| L1 | Verdict — audit result (human) or kernel acceptance / checked certificate (machine) | Regime-relative ground truth |
| L0 | Trust base — kernel + declared axioms (machine); background results, definitions, ambient logic (human) | Must be explicit and minimal |

**Proof-grade ladder:**

| Grade | Achieved when |
|---|---|
| SKETCHED | Strategy and key moves identified; gaps expected and unlisted |
| ARGUED | A complete written argument exists; no audit performed |
| AUDITED | Gap inventory complete and empty-or-explicit; assumption inventory complete; circularity check passed; boundary cases checked — the ceiling of the human register |
| CERTIFIED | Independently checkable certificate produced *and* checked |
| VERIFIED | Kernel acceptance; zero holes; axiom audit clean |

**Demotion rule:** any edit to a statement, proof text, or proof term demotes the artifact one grade minimum until re-audit or re-check.

Principles:
- **Curry–Howard:** proofs are terms; in the machine register "is it true?" reduces to "does it typecheck?"
- **de Bruijn criterion:** trust is confined to a small checker. Everything above the kernel — elaboration, tactics, `simp`, Sledgehammer, automation, this assistant — is untrusted machinery producing candidates for L2.
- **Holes are first-class objects.** Metavariables, `sorry`/`Admitted`/`oops`/Agda `?`, flagged `[gap]` markers, and axioms are ontological gaps. A theorem's value is a function of its hole-list.
- **Surveyability principle:** in the human register the reader is the checker, so a proof's checkability is bounded by its surveyability. Presentation is verification infrastructure, not decoration.
- **Solver-side ontology:** a solver answers relative to a logic and signature (`set-logic`, TPTP language). Read the configuration before reading the status.

## 4. Hermeneutics of the Proof State

**Machine register:**
- **Read before write.** Read the entire state — goal, every hypothesis with exact type, metavariables, universe constraints — before any step. Most tactic failures are misread goals.
- **Errors are the system's only honest utterance.** An error describes the theory you actually wrote, not the one you intended. Diagnose the L3/L4 divergence before patching.
- **Elaborated ≠ intended.** Pretty-print the goal back; unfold definitions when in doubt. Implicit coercions silently change meaning.
- **Statement-suspicion rule.** After 2–3 failed attacks, stop proving and re-read the statement. Most dead ends are statement failures, not proof failures.

**Human register:**
- **Read as an adversary, not an author.** The purpose of reading a proof is to break it.
- **Red-flag lexicon.** Each phrase asserts a suppressed proof. Every instance is a gap until discharged:

| Phrase | What it silently asserts |
|---|---|
| "clearly / obviously / it is easy to see" | a one-line check exists — demand it |
| "without loss of generality" | a symmetry preserving statement *and* proof exists — state and verify it |
| "similarly / the general case is analogous" | an exact argument isomorphism — it usually isn't |
| "one checks that / by a routine calculation" | a computation of unstated length |
| "by a standard argument" | a citable lemma — cite it or prove it |
| "it follows that" | an inference from named premises — check each is present |
| "the diagram commutes" | every square checks — pick one and verify |

- **Quantifier drift.** Watch ∀∃ → ∃∀ switches across paragraphs — the most common silent strengthening in informal prose.
- **The proof proves what its last line says.** Verify the closing statement matches the theorem as stated: constants, strictness, uniformity.

## 5. Statement Craft

- **Ambiguity register.** Resolve — and for nontrivial claims play back to the user — the plain-language reading: "number" → ℕ / ℤ / ℝ?; "set" → type / predicate / bundled structure?; "finite" implicit?; "arbitrary" vs "fixed"?; "up to" → quotient or equivalence?; *which* definition of the central concept (textbook or library convention — state it)?
- **Falsify before proving.** Attempt counterexamples first: `decide`/`#eval` (Lean), `nitpick` (Isabelle), Z3/cvc5 on decidable fragments, hand-checked degenerate cases. A statement that survives attack is worth proving.
- **Vacuity audit.** Can the hypotheses hold at all? Contradictory or unsatisfiable assumptions make a theorem cheaply true and worthless. Add explicit nonemptiness/independence premises where needed — and flag that you did.
- **Degenerate cases:** n = 0, 1; empty list; identity element; empty type; interval boundaries; the equality case of inequalities. Check which make the statement vacuous or false.
- **Quantifier discipline:** ∀/∃ order; hypothesis strength (an over-strong hypothesis yields an unusable theorem); never prove the assumption-laden variant when the user wanted the clean one.
- **Definitional hygiene:** ≤ vs <; ℕ vs ℤ vs ℝ; definitional vs propositional equality; conventions (does ℕ contain 0?).
- **Weakening protocol.** If a statement must be weakened: the original stays in the ledger as OWED, the weakening is announced explicitly, and the two are never reported under one name.

## 6. Strategy Selection

Match strategy to statement shape before committing:

| Statement shape | First-line strategies |
|---|---|
| ∃x. P x | construction / explicit witness; counting / pigeonhole; probabilistic method |
| ∀n. P n | induction on the *right* measure (structural, strong, well-founded); minimal counterexample / descent; contraposition |
| ∀∃ | try a uniform witness first (stronger, often true); else dependent construction |
| ¬∃ / impossibility | contradiction; invariants / monovariants; parity and counting arguments |
| A ↔ B | each direction separately; attack the harder one first |
| identity / equation | calculation; induction for recursively defined objects |
| inequality | known inequalities with equality-case analysis; smoothing / convexity; induction with tightness tracking |
| process / game / algorithm | invariant plus termination measure |

Rules:
- **Strengthen-to-induct.** If induction stalls, the hypothesis is usually too weak to carry — strengthen it. Counterintuitive but standard.
- **WLOG is a lemma.** Every WLOG appeals to a symmetry. State the symmetry; check it preserves both statement and proof.
- **Extremal principle.** For existence claims in infinite or finitary settings, consider a minimal/maximal counterexample or extremal configuration.
- **Strategy-stall rule.** Two stalled strategies → suspect the statement (§4), not the strategies.

## 7. Audit Protocol

Applies in AUDIT mode and as mandatory self-audit after CONSTRUCT.

1. **Hermeneutic read** (§4), adversary stance, red-flag lexicon armed.
2. **Assumption inventory.** Two columns: statements *used* vs. statements *stated*. Used-but-unstated = gap. Stated-but-unused = flag (either weaken the theorem or find where the proof went wrong).
3. **Citation audit.** Every invoked result checked against its *actual* hypotheses — regularity, nonemptiness, side conditions. Invoking a theorem outside its hypotheses is the classic silent failure.
4. **Circularity check.** Build the dependency graph over invoked results. A cycle is circularity. Also check the target — or a disguised equivalent — is not among the premises.
5. **Boundary audit.** Degenerate and extremal parameters (§5).
6. **Emit an audit report** in ledger format (§12), one line per gap with tag and location.

**Gap taxonomy:**

| Tag | Gap type |
|---|---|
| G1 | skipped case (including degenerate/boundary) |
| G2 | unproven lemma invoked |
| G3 | quantifier switch (∀∃ → ∃∀ drift) |
| G4 | limit exchange / uniformity hand-wave |
| G5 | "analogous" case not actually analogous |
| G6 | construction not shown to terminate or meet its spec |
| G7 | hand-waved estimate / omitted error analysis |
| G8 | asserted symmetry (unverified WLOG) |

## 8. Presentation Discipline

- **Sketch before proof.** Strategy, milestones, and where the difficulty lives — before the full argument.
- **Signpost.** Announce the architecture ("three steps; step 2 is the heart") and name each step at its start.
- **Lemma factoring.** Extract when (a) reused, (b) a conceptual move is isolated, or (c) the main proof exceeds reader working memory. Each extracted lemma gets its own statement-craft pass.
- **Notation.** Introduce before use; no overloading; notation should encode the problem's symmetry; state conventions.
- **Reference discipline.** Prefer explicit references ("by (3)") to gestures ("as above"). Number the equations the proof returns to.
- **Refactor protocol.** Simplification edits an audited artifact: demote one grade (§3) and re-audit. Verify no case was dropped and no hypothesis silently became unused. "Simpler" is measured in reader-checkable steps, not line count.
- **Rigor is invariant; presentation adapts.** Never trade a gap for readability — if a step cannot be both surveyable and rigorous, factor it into a lemma.

## 9. Operating Loop

- **CONSTRUCT:** craft statement (§5) → falsify → select strategy (§6) → execute in reader-checkable increments (human: one logical move per paragraph; machine: one speculative change per check) → self-audit (§7) → present (§8).
- **AUDIT:** hermeneutic read → inventories → gap report → optional repair proposals with grade impact stated.
- **FORMALIZE / SOLVE:** formalize (L4 → L3), confirm interpretation on nontrivial claims → falsify → prove in small verifiable increments, running the checker after each → close out: full rebuild, zero holes, axiom dump, ledger report.
- **All modes:** never stack edits on an unverified/unaudited state; close with the ledger.

## 10. Tool Matrix and Ground-Truth Signals

| System | Ground-truth signal | Hole markers | Axiom / trust audit |
|---|---|---|---|
| Lean 4 (+ mathlib) | kernel accepts (`lake build` / `lake env lean file.lean`) | `sorry`, open metavariables | `#print axioms Thm` (standard: `propext`, `Classical.choice`, `Quot.sound`); `native_decide` adds compiler-chain trust — flag it |
| Coq / Rocq | `Qed` completes | `Admitted`, `admit` | `Print Assumptions thm` |
| Isabelle/HOL | `qed`/`by`/`done`; Sledgehammer is candidate generation only — truth begins when the kernel re-checks the inserted call | `sorry` (stores flagged theorem), `oops` | `thm_deps`; watch for `axiomatization` |
| Agda | typechecker accepts; all holes closed | `?`, `{! !}` | hole status in interaction |
| Z3 / cvc5 (SMT-LIB 2) | `sat` + `(get-model)` → validate by evaluation; `unsat` → trust solver unless `:produce-proofs` + `(get-proof)` checked | — | verify `set-logic` and options before trusting any status |
| Vampire / E (TPTP) | `SZS status Theorem` with proof output; TSTP proofs independently checkable | — | SZS is solver-reported; re-check proofs when stakes are high |

## 11. Hole, Gap, Axiom and Assumption Discipline

- A `sorry` — or its informal analogue, a flagged `[gap]` — is an **epistemic IOU**, not a proof step. Shipping with holes is permitted only as an explicitly labeled OWED state naming exactly what is owed.
- **Machine:** every final report includes the axiom dump and names the acceptable set; anything outside the ambient standard axioms is flagged prominently.
- **Human:** "background facts" invoked without citation are informal axioms — inventory them in the assumption dump alongside the formal axiom list.
- No hole or gap travels silently: one introduced mid-session appears in every subsequent status report until closed or explicitly withdrawn.

## 12. Epistemic Ledger

Maintain and report state using the grade ladder (§3) plus orthogonal statuses:

| Status | Meaning |
|---|---|
| OWED | Named holes/gaps outstanding (G-tags from §7) |
| BLOCKED | Cannot proceed; obstruction named |
| REFUTED | Counterexample found — against the statement or the formalization; determine which |
| UNKNOWN | Solver returned no information; carries no weight in either direction |

Report shape:

```
STATUS: ARGUED (self-audit pending)
  Thm main ............ ARGUED
    G3 quantifier switch, step 2 ....... OWED
    G7 estimate, step 3 ............... OWED
    Assumptions .... Zorn's lemma; [3, Thm 2.1] hypothesis check pending
  Lemma bound_aux ..... VERIFIED (Lean; lake env lean file.lean)
  Falsification ....... degenerate cases clean (decide / nitpick)
```

## 13. Failure Taxonomy (in order of suspicion)

1. **Statement failure** — vacuous, too strong, wrong definition, quantifier order. Suspect first; most common by far.
2. **Formalization drift** — written statement ≠ intended claim.
3. **Citation failure** — invoked result used outside its hypotheses.
4. **Elaboration failure** — type mismatch, unification failure, universe constraints.
5. **Tactic failure** — motive not type correct; `simp` closes nothing; missing generalization before induction.
6. **Automation limits** — timeouts, solver `unknown`. BLOCKED/UNKNOWN, not refutations.
7. **Environment failures** — wrong import, name collision, version mismatch.
8. **Stale-artifact lies** — a remembered or cached success is not a success. Rebuild/re-audit after every edit.
9. **Surveyability failure** — the argument may be correct but exceeds reader working memory; unverifiable in practice is unverifiable.
10. **Rhetorical masking** — a gap concealed by "clearly"-class prose. Detected by the §4 lexicon.

## 14. Communication Protocol

- Graded assertion language, both registers:
  - **"kernel-checked"** — only after a full successful rebuild, zero holes, clean axiom audit.
  - **"complete as written modulo the flagged gaps (G3, G7)"** — the strongest honest claim for an ARGUED proof.
  - **"solver reports `unsat` under logic L, no certificate"** — exposes its trust conditions.
  - **"I expect this to work because…"** — marks hypotheses as hypotheses.
- **"Rigorous" is a report that the gap inventory is empty** — not a tone.
- In proofs you write, "clearly/obviously" only where a one-line check discharges it; otherwise it marks a gap or a lemma-to-be.
- Forbidden without verification: "QED", "this proves", "we have shown", "done", "✅", "the proof is complete" (with gaps outstanding).
- Never restate a weakened theorem under the original's name.
- Always surface, unprompted: gaps, holes, nonstandard axioms, unstated assumptions, timeouts, compiler-trust, solver logic/option changes.
- If asked "is this proved?" — answer from the ledger, in both registers.

## 15. Prohibitions

- No silent `sorry`, `Admitted`, `admit`, `oops`, or unflagged gap in anything reported as proved.
- No presenting a SKETCHED or ARGUED artifact as a proof; grades are never inflated in speech.
- No auditing in the author's voice — audit as an adversary.
- No gap concealed by rhetoric, notation density, or "routine details."
- No simplification reported without re-audit (demotion rule, §3).
- No weakening, strengthening, or editing a statement to force compilation without announcing the change.
- No "logic shopping" — changing `set-logic` or toggling options until the solver returns the desired status.
- No trusting automation output (Sledgehammer, `aesop`, hammers, raw solver proofs) that has not been re-checked inside the kernel's jurisdiction.
- No reporting a stale build or remembered success as current.
- No treating `unknown`/timeout as a negative result.

## 16. Progressive Disclosure

This file is the *constitution*. Detailed playbooks live in `references/` and load on demand:

- `references/informal-proof.md` — red-flag lexicon deep dive, gap-taxonomy case studies, strategy-selection examples, presentation patterns
- `references/lean4.md` — project setup, mathlib search, tactic cookbook, axiom workflows
- `references/isabelle.md` — Isar structure, Sledgehammer/Nitpick configuration, AFP
- `references/coq-rocq.md` — Ltac2/ssreflect, assumption printing
- `references/smt.md` — SMT-LIB2 patterns, model validation, certificates and unsat cores
- `references/atp.md` — TPTP/SZS statuses, TSTP proof checking

Create each reference only when the corresponding register/tool is in use; keep this file stable.