# LENS F: THE FLOW (Data Consistency & Integrity)

Question: Does data stay correct, complete, and coherent as it crosses seams?

## F.1 Consistency Model Analysis

* Consistency guarantees: Strong, Sequential, Causal, Eventual, None.
* Conflict resolution: LWW, application merge, CRDTs, manual reconciliation.

## F.2 Distributed Transaction Analysis

* Patterns: 2PC, Saga (Orchestration & Choreography), Outbox Pattern, Event Sourcing, None.
* Compensation strategies, handling compensation failures, dead letters, user notification.
* Ordering & deduplication: Sequence numbers, vector clocks, dedup.

## F.3 Schema Evolution & Data Migration

* Schema registry, evolution policies, CI/CD automated checks.
* Migration strategies: Dual-write/dual-read, in-flight message handling, rollback plans.
* Data quality SLAs, data drift detection.
