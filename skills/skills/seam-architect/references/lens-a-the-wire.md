# LENS A: THE WIRE (Technical Integration)

Question: How do these systems physically communicate?

## A.1 Protocol & Transport Analysis

For each seam, classify:

* PROTOCOL: REST/HTTP (HTTP/1.1, HTTP/2, HTTP/3), gRPC (unary, server-streaming, client-streaming, bidirectional), GraphQL (query, mutation, subscription), Message Queue (Kafka, RabbitMQ/AMQP, AWS SQS, Azure Service Bus, NATS), Event Stream (Kafka Streams, AWS Kinesis, Pulsar), WebSocket / SSE, File Transfer (SFTP, S3 bucket drop, shared NFS), Shared Database (direct table access, shared schema, database link), RPC (SOAP, XML-RPC, custom binary), Webhook (HTTP callback)
* SERIALIZATION: JSON, Protobuf, Avro, MessagePack, XML, CSV, custom binary
* TRANSPORT SECURITY: TLS version, certificate management, mTLS, plaintext (flag as critical risk)
* DISCOVERY: Hardcoded URLs, DNS-based, service registry (Consul, Eureka), service mesh (Istio, Linkerd), API gateway routing

## A.2 Coupling Classification

COUPLING SPECTRUM (classify each seam):

* LEVEL 1 - TEMPORAL COUPLING: Both systems must be running simultaneously. Synchronous request/response (REST, gRPC unary). Risk: Cascading failures, latency amplification.
* LEVEL 2 - BEHAVIORAL COUPLING: Consumer depends on specific producer behavior/logic. Shared business rules, orchestration patterns. Risk: Synchronized deployments, knowledge leakage.
* LEVEL 3 - CONTRACT COUPLING: Consumer depends on the shape of the data contract. API schemas, message formats, field names. Risk: Breaking changes, version hell.
* LEVEL 4 - PLATFORM COUPLING: Both systems must share infrastructure. Shared database, shared file system, same cloud provider APIs. Risk: Blast radius expansion, migration impossibility.
* LEVEL 5 - IDENTITY COUPLING: Systems share identity/naming conventions. Shared user IDs, order numbers, entity references. Risk: Namespace collisions, referential integrity gaps.
* LEVEL 6 - DEPLOYMENT COUPLING: Systems must be deployed together. Monolithic deployments, shared libraries with runtime dependencies. Risk: Agility destruction, "deploy everything" syndrome.

Rate each seam: LOOSE / MODERATE / TIGHT / FUSED. Flag any seam rated TIGHT or FUSED as requiring immediate attention.

## A.3 Resilience Pattern Inventory

For each seam, verify presence/absence of:

* Circuit Breaker (Closed -> Open -> Half-Open states)
* Retry with Exponential Backoff + Jitter
* Timeout Configuration
* Bulkhead / Isolation
* Dead Letter Queue (DLQ) / Poison Pill Handling
* Idempotency
* Backpressure
* Graceful Degradation
* Health Checks

Mark each: ✅ PRESENT | ⚠️ PARTIAL | ❌ ABSENT | ❓ UNKNOWN

## A.4 State & Idempotency Analysis

1. Is the operation stateless or stateful?
2. If repeated N times, is the outcome identical to executing once?
3. What is the idempotency mechanism? (Natural GET/DELETE, Idempotency Key, Conditional writes, Deduplication at consumer)
4. What happens during "exactly once" vs "at least once" delivery disputes?
5. Is there a saga or compensation mechanism for multi-step operations?

## A.5 Contract Definition & Evolution

1. CONTRACT HEALTH CHECK: Is the contract explicitly defined? (OpenAPI, Protobuf/Avro, AsyncAPI, PACT) Or is it implicit?
2. VERSIONING: URL versioning, Header versioning, Schema registry.
3. COMPATIBILITY: Backward, Forward, Full compatibility, or Breaking changes with windows.
4. CONTRACT TESTING IN CI/CD: Provider verification, Consumer-driven contract tests (PACT), Schema compatibility checks.
5. DEPRECATION: Deprecation headers, Sunset policies, Multi-version support windows.
