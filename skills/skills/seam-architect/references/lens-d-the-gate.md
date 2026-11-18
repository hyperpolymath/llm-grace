# LENS D: THE GATE (Security Boundaries)

Question: What trust assumptions change at this seam, and are they defended?

## D.1 Trust Boundary Classification

* LEVEL 0 - INTRA-PROCESS: Same process, same trust domain.
* LEVEL 1 - INTRA-SERVICE MESH: Different processes, same managed network, mTLS enforced.
* LEVEL 2 - INTRA-ORGANIZATION CROSS-NETWORK: Different VPCs/networks, same org.
* LEVEL 3 - THIRD-PARTY INTEGRATION: Crossing organizational boundaries (SaaS, partners). Zero trust.
* LEVEL 4 - PUBLIC INTERNET FACING: Exposed to untrusted clients. Maximum defense.

## D.2 Authentication & Authorization at the Seam

* AUTHENTICATION: mTLS, OAuth 2.0 / OIDC, API Key, JWT, HMAC Signature, None.
* AUTHORIZATION: Scope-based, RBAC, ABAC, Network-based, None.
* IDENTITY PROPAGATION: End-user identity pass-through, token exchange, confused deputy defense.
* SECRET MANAGEMENT: Vault, environment variables, config file, rotation policies.

## D.3 Data Security at the Seam

* DATA IN TRANSIT: TLS 1.2+, cipher suites, CA chain/pinning.
* DATA CLASSIFICATION: PII/PCI/PHI handling, field-level encryption, masking/tokenization, least privilege.
* DATA RESIDENCY: Geographic boundaries, GDPR/sovereignty, audit logs.
* INPUT VALIDATION: Schema validation, size/type/range limits, SQLi/XSS/Command Injection defenses.

## D.4 Rate Limiting & Abuse Prevention

* Rate limiting strategies (fixed, sliding, token/leaky bucket).
* Rate limit headers returned.
* Tiered limits, DDoS mitigation, abuse detection, quarantine capabilities.
