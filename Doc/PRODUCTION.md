# Plenact Production Database/API Readiness

## Purpose And Status

This document is a future-facing architecture and readiness reference for using the Plenact database API pattern in the Plenact app. It is not a production authorization design, deployment approval, or claim that the demo can be copied unchanged into production.

The proven demo topology is:

```text
Native iOS app -- HTTPS/JSON --> PHP API on Bluehost --> MySQL-compatible database
```

The app does not connect directly to MySQL. Database credentials remain in private server configuration outside the public web root.

### Demo Baseline

As of 2026-10-01, the user has reported successful foreground health checks, authenticated bootstrap reads, and Favorite Food/#Cats writes and readback from the Simulator and a physical iPhone. The demo uses an app token stored in Keychain, a server-configured installation identifier, and one current preferences row for that identifier. These choices prove the transport and database flow; they do not establish production user identity or tenant isolation.

The development host is documented as PHP 8.2 and Percona 5.7-compatible. Local PHP syntax checks have been run with PHP 8.5. Confirm the actual host runtime and database version before relying on version-specific behavior.

Credential rotation was identified as necessary because populated private configuration appeared in Git history and a shared archive. Rotation and revocation of every exposed value must be verified separately before the development setup is shared again. Git ignore rules alone do not remove secrets from existing history or archives.

## Production Boundary

Treat the demo as a source reference for:

- HTTPS JSON requests between an iOS client and a server API.
- Request validation at both the client and server.
- Private server-side database configuration.
- Prepared database statements and explicit response handling.
- Additive schema migrations and focused end-to-end verification.

Do not copy these demo properties into production without redesign:

- A shared app token entered by a human and distributed to mobile clients.
- A server-wide installation identifier used to select a single row.
- Demo preference fields or demonstration error messages as Plenact's product contract.
- Development database names, credentials, URLs, paths, or configuration files.

Keychain protects a token at rest on the device, but cannot make a shared mobile-app credential secret from a determined device owner. A token that authorizes every installation is not a user authentication system.

## Decisions Required For Plenact

Resolve these decisions before implementing production-backed app features. Record the chosen option and rationale in a reviewed architecture decision record.

| Decision | Questions to answer | Required outcome |
| --- | --- | --- |
| User authentication | Which identity provider or account system authenticates a Plenact user? How are tokens issued, refreshed, revoked, and expired? | A documented, supported login and token lifecycle; no shared permanent app secret. |
| Authorization | Which user, role, or service may read or change each record? How are role changes and revocation enforced? | Server-side authorization for every operation, with least privilege. |
| Data ownership | Are records owned by a user, organization, workspace, or another entity? How is membership established? | A stable owner key derived from authenticated server identity, never trusted from an unverified client field. |
| Reader access | Which separate client or service needs read access, and to which fields? | Explicit reader scopes, output filtering, and a distinct access policy from writes. |
| Data retention | What data is retained, for how long, and how can users export or delete it? | Product-approved retention, deletion, backup, and audit rules. |
| Environments | Which development, test, staging, and production hosts, databases, and accounts exist? | Isolated resources and credentials for each environment. |
| Operations owner | Who deploys, rotates credentials, applies migrations, restores backups, and responds to incidents? | Named operational responsibilities and runbooks. |

## Authentication And Authorization

- Authenticate a person or trusted service with an established identity system appropriate to Plenact's requirements. Do not treat the demo's 64-character shared token as proof of user identity.
- Keep database credentials exclusively on the server. Never compile them, embed a global database key, or package them in the app.
- Validate access tokens on the server, including signature or introspection, issuer, audience, expiry, and required scopes as applicable to the selected identity system.
- Derive the authenticated subject and tenant context on the server. Do not select data ownership from a request-supplied `user_id`, `organization_id`, or demo `installation_id` without verifying membership and access.
- Enforce authorization for reads and writes at the record boundary. A reader role must not inherit write permission, and a valid token alone must not imply access to every tenant's data.
- Return the minimum fields needed for each client workflow. Avoid broad bootstrap responses that expose unrelated account data.
- Use generic authentication and authorization failures. Do not return token contents, private configuration, database names, filesystem paths, stack traces, or SQL diagnostics.
- Define secure token storage, refresh, revocation, and logout behavior on each client. Do not log credentials or place them in URLs, analytics, crash reports, or screenshots.

## Data Ownership And Schema

The demo's `installation_preferences` primary key is a server-configured installation ID. It intentionally makes the Simulator and physical iPhone use one configured record. Plenact production data will likely require user- or organization-scoped ownership instead.

Before defining production tables:

1. Draw the ownership relationships between users, organizations/workspaces, memberships, and each protected record.
2. Choose stable keys and database constraints that prevent cross-tenant access and duplicate ownership records.
3. Define whether each write replaces current state, appends history, or creates an auditable event.
4. Define deletion, archival, retention, and privacy requirements before data is collected.
5. Document UTC timestamp semantics, nullability, maximum lengths, numeric ranges, and normalization rules.
6. Consider optimistic concurrency or version fields where simultaneous updates or stale clients could overwrite newer data.
7. Keep operational installation status separate from user-owned product data unless an explicit data model says otherwise.

The demo preference endpoint implements last-write-wins for one configured installation. That is not automatically appropriate for collaborative, multi-user Plenact data. For queued or retryable writes, define idempotency and stale-update behavior before implementation. For sequenced status reports, define sequence allocation, duplicate handling, and rejection of stale reports separately from preference semantics.

## Complex Datasets, Provenance, And Revisions

Plenact datasets may contain nested, large, or evolving content that needs more than a mutable value column. Define the dataset's ownership, storage representation, metadata, revision semantics, and retrieval contract before choosing tables or endpoint shapes. The examples below are design concepts; field names are illustrative, not a proposed Plenact schema.

### Provenance Metadata

For each stored dataset or revision, decide which provenance metadata is required. A typical starting set is:

| Metadata | Recommended source and meaning |
| --- | --- |
| Dataset identity | Stable server-issued ID for the logical dataset; do not treat a client-chosen ID as authorization. |
| Owner scope | User, organization, workspace, or other owner derived from verified server-side identity and membership. |
| Storage author | Authenticated actor subject derived by the API from the validated session/token. Never trust a request-supplied author field. |
| Storage date | Server-generated UTC timestamp for when the write is accepted or committed; document which event it represents. |
| Dataset revision | Server-assigned, monotonically increasing revision within the dataset's defined scope. Do not trust the client to choose the next revision. |
| Data schema version | Version of the payload structure/interpretation, separate from the dataset revision number. |
| Change reason | Optional, validated user- or service-provided explanation when product or audit requirements call for one. Do not store secrets here. |
| Content hash | Optional integrity aid over a precisely defined canonical representation; it is not an authorization check or substitute for a signature. |

Prefer a stable, non-display principal identifier for `stored_by`. Resolve display names separately and according to privacy policy; names can change and may be personal information. Set timestamps in UTC on the server/database rather than accepting client clock values as authoritative.

### Storage Representation

Choose storage based on how Plenact will validate, query, index, update, and retain the data:

- **Relational columns/tables:** Prefer for fields with stable types, constraints, joins, filtering, aggregation, or access-control significance.
- **JSON document:** Consider for nested or evolving payload sections that are usually read and written as a unit. Validate against an explicit, versioned schema before storing; keep identity, ownership, revision, and query-critical fields relational.
- **Hybrid model:** Store ownership and version metadata relationally and the structured payload as relational data or a validated JSON document, based on query needs.
- **External object storage:** Consider for large binary assets or files. Store an opaque reference and integrity metadata in MySQL; enforce authorization when issuing access to the object.

Do not choose a single opaque JSON blob merely because the client can encode one. Establish maximum payload size, encoding, schema-version rules, indexing needs, backup behavior, and compatibility with the exact Bluehost database engine/version. Keep secrets and authorization claims out of user-controlled dataset content.

### Revision Semantics

Decide whether Plenact needs only the current dataset, an auditable history, or both:

1. **Current state with revision counter:** Update one current record and increment its revision atomically. This is compact but does not preserve prior content unless a separate audit/history record is written.
2. **Immutable revisions with a current pointer:** Insert each accepted version as a new immutable revision and update a dataset record's current-revision pointer in the same transaction. This supports history and rollback, but requires retention and access rules for old versions.

For either model:

- Define revision scope and starting value; enforce uniqueness such as `(dataset_id, revision_number)` where applicable.
- Allocate revisions on the server within a transaction or another concurrency-safe operation. Never calculate `MAX(revision) + 1` outside a transaction and assume it is unique.
- Let clients submit an expected current revision or equivalent conditional-update token when stale overwrites matter. Return a conflict response such as HTTP 409 when the expected revision is no longer current.
- Define whether retries are idempotent. A client retry must not accidentally create a second revision or apply the same operation twice; use an idempotency key or stable operation ID where needed.
- Store the payload, author, timestamp, revision, and current-pointer/audit changes atomically. A partial metadata-only or payload-only write must not look successful.
- Specify whether historical revisions may be read, restored, redacted, or deleted, and how retention/legal deletion interacts with audit requirements.

### Retrieval Contract

Define both current and historical reads before implementing them:

- Scope every lookup by verified owner/tenant context, not merely by a dataset ID supplied by the caller.
- Specify whether the default read returns the current revision, a requested revision, or a paginated history.
- Return an explicit revision number, data schema version, server storage timestamp, and an appropriate actor identifier when the caller is authorized to see that metadata.
- Document pagination, stable ordering, filters, maximum page size, cache policy, and behavior when a dataset or revision is absent.
- Apply the same authorization checks to historical versions, exports, and restore operations as to current data; older revisions can contain data no longer visible in the current version.
- Avoid exposing internal object-storage paths, private keys, or other tenants' metadata in responses.

### Dataset Readiness Checks

Before a Plenact dataset feature is production-ready, verify that:

- Ownership and storage-author identity come from trusted server-side context.
- Timestamps are generated and interpreted consistently in UTC.
- Dataset revision and payload schema version are distinct and tested independently.
- Concurrent updates, stale clients, retries, and partial failures have defined outcomes.
- Reads of current and historical data enforce tenant authorization and bounded pagination.
- Migrations, retention, deletion, backup/restore, and payload compatibility have tests and runbooks.

## API Contract

For each endpoint, document:

- Purpose, owner, HTTP method, path, required authentication, and authorization scope.
- Request media type, maximum body size, fields, JSON types, ranges, and normalization.
- Success status, response shape, nullability, and whether the result is cached.
- Stable error codes and status mappings for invalid input, authentication, authorization, conflict, rate limiting, dependency failure, and unexpected server errors.
- Idempotency and concurrency semantics for writes.
- Pagination, sorting, filtering, and field selection for collection reads.
- Compatibility/versioning policy for future clients and server deployments.
- Logging and audit fields that are permitted, excluding credentials and unnecessary personal data.

Validate all request values on the server even when the app performs matching checks. Use parameterized SQL, strict JSON types, bounded request sizes, and a consistent versioned contract. Keep detailed internal failures in access-controlled server diagnostics; expose only safe, actionable API errors.

## Database And Credential Operations

- Use a dedicated database and least-privilege database account for each environment and service boundary. Grant only the operations and schemas the API actually requires.
- Keep private configuration outside the public web root. Restrict directory and file permissions, use a controlled secret store where available, and never include populated configuration in Git or shared archives.
- Separate development, staging, and production hostnames, databases, users, tokens, and deployment procedures. Do not point a test build at production by accident.
- Rotate exposed credentials, revoke old values, record the rotation date and owner, and verify old credentials fail. History cleanup and archive review are separate tasks; rotation does not erase leaked copies.
- Keep error display disabled in deployed PHP endpoints. Use server-side logs with access controls and redaction; never log bearer tokens or raw secret configuration.
- Use HTTPS for all app/API traffic. Set explicit cache policy for private responses and verify TLS configuration on the deployed host.
- Plan request timeouts, bounded retries, rate limiting, abuse monitoring, and safe behavior during database/API outages. Retries of writes require idempotency or a documented replacement policy.

## Schema Migration And Release Process

1. Write each schema change as a separately reviewed, additive migration where practical. Give it a unique ordered identifier and document prerequisites and expected effects.
2. Never rerun an initial schema script against a populated database. Record which migrations have been applied in each environment.
3. Test migrations against a disposable database with the same supported MySQL/Percona version and relevant configuration as the target host.
4. Take and verify a backup before a production migration. Document rollback or forward-repair steps; destructive rollback is not assumed safe.
5. Deploy server code and schema in an order that remains compatible during the transition. Document any required maintenance window or temporary compatibility behavior.
6. Verify schema, endpoint health, authorized and unauthorized requests, representative reads and writes, and monitoring after release.
7. Keep release artifacts and deployment paths limited to the intended Plenact environment. Do not publish temporary probes or private configuration.

## Test Strategy

Build checks at several levels before production use:

- **Unit tests:** validators, request/response mapping, ownership checks, and error translation.
- **API tests:** correct method and content type; missing, malformed, expired, and insufficient-scope credentials; valid and invalid payloads; request-size limits; and stable error codes.
- **Authorization tests:** user A cannot read or modify user B's records; organization membership changes take effect; reader permissions cannot write.
- **Database integration tests:** migrations apply once, constraints reject invalid values, prepared statements handle quoted/unicode input, writes obey idempotency/version rules, and rollback/recovery steps are exercised.
- **Client tests:** token absence, expired session, connectivity loss, server errors, decoding failures, stale drafts, and repeated user actions.
- **End-to-end tests:** supported app build -> staging API -> staging database, with representative success and denial cases on Simulator and physical devices.
- **Operational tests:** backup restore, credential rotation/revocation, deployment rollback or forward repair, alerting, and safe diagnostic logging.

Never run destructive or schema tests against production data. Use synthetic accounts and records in isolated test environments.

## Readiness Gates

Do not describe a Plenact database feature as production-ready until all relevant gates are satisfied:

- [ ] The Plenact identity, authorization, and tenant-ownership model is documented and reviewed.
- [ ] No shared database credential or permanent global app token is required by the client.
- [ ] Every read and write is authorized against server-derived ownership.
- [ ] API contracts, validation, errors, versioning, and write semantics are documented.
- [ ] Development, staging, and production resources are isolated.
- [ ] Database grants are least-privilege; secrets remain private and rotation/revocation are tested.
- [ ] Migrations, backups, recovery, and release procedures are tested against the supported database version.
- [ ] Cross-user authorization, invalid inputs, retries, and failure cases have automated coverage.
- [ ] Monitoring, safe logs, incident ownership, and operational runbooks are in place.
- [ ] Privacy, retention, deletion, and audit requirements are approved for the data being stored.

## Open Plenact Decisions

This reference deliberately does not choose Plenact's identity provider, tenant model, production schema, API versioning policy, data-retention rules, or Bluehost production topology. Resolve and record those decisions with the product and security requirements before adapting the demo endpoints.