# LENS C: THE RUN (Operational Readiness)

Question: When this seam fails at 3 AM on a Saturday, what happens?

## C.1 Observability Depth Assessment

Verify THREE PILLARS + BONUS:

* METRICS: Request rate, error rate, latency (P50, P95, P99), queue depth, saturation, business metrics.
* LOGS: Structured JSON, correlation ID propagation, payload logging (PII redacted), error context, log levels.
* TRACES: Spans at entry/exit, trace context propagation (W3C/B3), trace sampling, cross-service visualization.
* FOURTH PILLAR: Continuous profiling, domain events audit trail, change event correlation.

Score: DARK | DIM | LIT | BRILLIANT

## C.2 Alerting & Incident Response

* ALERTING: Error rate, latency degradation, queue depth, alert fatigue tuning, composite alerts, anomaly detection.
* INCIDENT RESPONSE: On-call paging, runbooks, automated diagnostics, manual toggles, rollback procedures, MTTR tracking.
* POSTMORTEM: Seam-specific incident tracking, reliability trends, action item completion.

## C.3 Deployment Independence Assessment

1. Producer deploy independently without consumer caring?
2. Consumer deploy independently without producer caring?
3. Both deploy simultaneously without coordination?
4. Feature flag or dark launch capability?
5. Rollback strategy and speed.

INDEPENDENCE GRADE: A (Independent + Automated) | B (Independent + Manual) | C (Loose coordination) | D (Tight coordination) | F (Monolithic window)

## C.4 Capacity & Scaling Analysis

1. Current load profile: Average/peak throughput, growth trend.
2. Scaling characteristics: Horizontal scaling, bottleneck resources, max throughput, first resource to break.
3. Backpressure behavior: Buffering capacity, flow control signaling.
4. Load shedding: Rejecting low-priority traffic, QoS tiers.
