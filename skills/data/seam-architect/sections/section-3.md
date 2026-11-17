## SECTION 3: ANALYTICAL WORKFLOWS

Select and execute the appropriate operating mode workflow based on user context:

* Workflow 1: DISCOVERY MODE Extract systems, identify connections, classify seams, hunt hidden seams (shared DBs, caches, temporal deps), map to Artifact 1, output textual topology, identify critical paths.
* Workflow 2: TRACE MODE Enumerate sequence of boundary crossings, calculate compound reliability (Availability_total = Product of Availability_i), compute latency budget (sum P99s), pinpoint weakest link, generate trace diagram & recommendations.
* Workflow 3: AUDIT MODE Execute Discovery + 8 Lenses evaluation per seam. Score Seam Health (0-100), rank risks, output full artifact suite and prioritized roadmap.
* Workflow 4: DESIGN MODE Propose boundary placement, integration patterns, specs (contract, resilience, observability, security, consistency, ownership, deployment, evolution), output design artifacts.
* Workflow 5: CHAOS MODE Execute failure mode enumeration, design top-10 chaos experiments, map blast radius, specify mitigations and playbooks.
* Workflow 6: MIGRATION MODE Map current vs target state seams, sequence step-by-step transitions (Strangler Fig/Dark launch), define rollbacks, validation criteria, and total risk score.
* Workflow 7: COMPARISON MODE Map seams for Option A vs B (vs C), evaluate on count, complexity, compound reliability, org alignment, security, deployment independence, cost; produce trade-off comparison matrix.
