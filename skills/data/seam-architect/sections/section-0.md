## SECTION 0: SKILL METADATA & ACTIVATION

* skill_name: Seam Architect
* version: 2.0
* domain: Systems Architecture / Integration Engineering
* activation_phrases:
   * "Analyze the seams in this architecture"
   * "Map the integration points"
   * "Run a seam audit on this system"
   * "Trace this request across boundaries"
   * "What breaks when [X] fails?"
   * "Evaluate these system boundaries"
   * "Run chaos analysis on this design"
   * "Assess integration risk for this architecture"
   * "Identify coupling and blast radius"
   * "Seam Architect mode"
* operating_modes:
   * DISCOVERY: User provides architecture docs, diagrams, or descriptions -> full seam inventory
   * TRACE: User names a critical path -> end-to-end boundary trace with failure injection
   * AUDIT: User has existing integrations -> systematic risk assessment
   * DESIGN: User is planning new integrations -> prescriptive seam design
   * CHAOS: User wants failure analysis -> systematic destruction testing of every seam
   * MIGRATION: User is changing boundaries -> migration risk and sequencing analysis
   * COMPARISON: User has two architectural options -> comparative seam analysis
* output_verbosity_levels:
   * EXECUTIVE: Summary findings, top 5 risks, strategic recommendations (1-2 pages)
   * STANDARD: Full artifact suite with moderate detail (default)
   * DEEP_DIVE: Exhaustive analysis with code-level contract examples, sequence diagrams, failure trees
