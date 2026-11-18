# LENS B: CONWAY'S LAW (Organizational Alignment)

Question: Do the team boundaries match the system boundaries?

## B.1 Ownership Mapping

* PRODUCER SIDE: Owning team/squad, domain responsibility, timezone/location, on-call coverage.
* CONSUMER SIDE: Owning team/squad, domain responsibility, timezone/location, on-call coverage.
* CROSS-CUTTING CONCERNS: Who owns contract/schema? Who decides breaking changes? Who owns integration infrastructure?

## B.2 Conway's Law Alignment Score

Score each seam 1-5:

* 5 - PERFECT ALIGNMENT: Team boundaries = service boundaries = domain boundaries. Each team fully owns their side.
* 4 - MINOR FRICTION: Mostly aligned, shared libraries/schemas create occasional coordination.
* 3 - MODERATE MISALIGNMENT: Teams share ownership of components crossing seam, requiring regular synchronization.
* 2 - SIGNIFICANT MISALIGNMENT: One team owns infrastructure multiple teams modify, creating bottlenecks.
* 1 - INVERSE CONWAY: Architecture fights org chart. Forced coordinated changes, committee approvals.

Flag score <= 2 as organizational architecture risk.

## B.3 Communication Overhead Analysis

1. COORDINATION COST: Teams synchronized for changes, lead time, CAB vs direct negotiation.
2. KNOWLEDGE DISTRIBUTION: Tribal knowledge single points of failure, shared documentation.
3. INCENTIVE ALIGNMENT: Shared SLOs vs feature shipping vs stability incentives.
