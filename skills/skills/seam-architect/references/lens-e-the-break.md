# LENS E: THE BREAK (Chaos & Failure Analysis)

Question: What is the worst thing that can happen at this seam, and are we ready?

## E.1 Failure Mode Enumeration

* AVAILABILITY: Complete down, partial down, zombie state, network partition, DNS failure, LB/Gateway failure.
* PERFORMANCE: 10x latency, gradual degradation, intermittent timeouts, pool exhaustion, GC pauses.
* DATA: Malformed, semantically wrong, schema mismatch, out of order, duplicates, data loss, corruption.
* SECURITY: Cert/Token expiration, unauthorized access, exfiltration, MitM.
* CAPACITY: 10x/100x traffic spike, storage exhaustion, consumer lag accumulation.
* OPERATIONAL: Bad deployments, misconfigurations, infrastructure shifts, cloud provider degradation.

## E.2 Blast Radius Mapping

* DIRECT IMPACT: Affected services, lost features, data at risk.
* CASCADING IMPACT (1st Order): Downstream seams affected, state degradation.
* CASCADING IMPACT (2nd Order): Secondary cascading failures, feedback loops (retry storms).
* AMPLIFICATION FACTORS: Stampedes, connection pool propagation.
* HUMAN / BUSINESS IMPACT: Customer impact, revenue/min, compliance, reputation.

Blast Radius: LOCAL | REGIONAL | GLOBAL | EXISTENTIAL

## E.3 Chaos Experiment Design

Structure experiments with Name, Target Seam, Hypothesis, Injection Method, Steady State Metrics, Abort Conditions, Containment, Expected vs Actual.

## E.4 Vendor & Technology Lock-in Assessment

Evaluate substitutability, switching cost (TRIVIAL / MODERATE / HIGH / LOCKED), proprietary API dependencies, abstraction layers, vendor track record. Risk Rating: LOW | MODERATE | HIGH | CRITICAL.

## E.5 Architectural Simplicity Audit

Identify complexity indicators (>3 hops, multiple transformations, ESBs/middleware, single-person tribal knowledge, separate integration repos). Suggest simplification candidates.
