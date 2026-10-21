# Implementation Plan

Phase status is factual as of 21 October 2026. Phase 0 foundation and Phase 1B Publisher/Solution setup are complete. Phase 1C's wider schema remains proposed. Explicit owner approval authorized Phase 1D-C for exactly `os_sr_ta`; creation and independent metadata verification are complete. Phase 2C adoption of existing AppModule `srapp` is approved; Phase 2D composition remains unauthorized. Other tables and later app/flow implementation are not authorized by those approvals.

On 20 October 2026 the owner explicitly approved applying `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc` with plurals Positions, Candidate Sources, and Locations. The first Position Apply POST returned HTTP 401; read-only reconciliation found no Position metadata and TA remains the only project table. Candidate Source and Location Apply were not attempted. The historical root cause is unknown; effective Global Entity/Attribute create and customization privileges were subsequently verified, but failed-request token expiry/challenge/IDs were not logged. Expiry-aware token refresh and sanitized response diagnostics are now implemented. Synthetic tests and fresh read-only DryRuns passed; Apply remains blocked pending diagnosis and a controlled recovery decision. No retry or later-table execution was made. See [Current State](CURRENT_STATE.md) and [Scripts](../scripts/README.md).

## Phase 0 — Repository Foundation and Blueprint

- **Objective:** Establish product context, governance, proposed design, and verifiable next steps.
- **Scope:** Markdown documentation and `.gitignore`; no Power Platform resources.
- **Dependencies:** Supplied draft blueprint and product rules.
- **Deliverables:** Repository guidance, architecture/business/security/integration proposals, plans, and acceptance criteria.
- **Acceptance:** Required files exist and contain meaningful content; links/frontmatter checked; no fake resources, secrets, or false status claims.
- **Validation:** File inventory, Markdown relative-link scan, YAML frontmatter parse, consistency/privacy/status review, Git diff/status.
- **Risks:** Missing historical references; assumptions mistaken for approved decisions.
- **Status:** Completed.

## Phase 1 — Dataverse Foundation

- **Objective:** Approve schema and establish governed data/business-operation foundation.
- **Scope:** Phase 1A/1B setup and the single approved Phase 1D-C TA table slice are complete. The wider Phase 1C schema, remaining Phase 1D tables, roles, and server-enforced operations require separate approval.
- **Dependencies:** Schema and security approval, ownership, keys, retention, call/visitor/result decisions, environment governance, connector identities, source mapping, and ALM approach.
- **Deliverables:** Detailed wider proposal in [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md); Publisher, unmanaged Solution, and only `os_sr_ta` with its approved name/email metadata verified. No roles, APIs, apps, flows, or business records created.
- **Acceptance:** Resolve design decisions; approve schema and security; verify keys/relationships/audit; then test permitted/blocked transitions and no duplicate status/history before implementation acceptance.
- **Validation:** Static logical-name/key/relationship review; read-only solution component check; executable Dataverse/API, authorization, concurrency, and audit tests only after a separately approved implementation.
- **Risks:** Candidate/TA identity and ownership, key value formats, field-level security vs keys, retention, external side effects, and legacy data semantics remain unresolved.
- **Status:** Phase 1B and approved Phase 1D-C TA-only deployment are complete. Phase 1D-D preparation is complete; Apply is owner-approved but blocked/partial at Position on HTTP 401. No Position metadata persisted and no subsequent targets were attempted. TA, audit settings, and security-role definitions remained unchanged. The approval does not authorize retry after an uncertain operation without resolving the authorization failure. Full Phase 1 acceptance and other-table implementation remain pending. See [Current State](CURRENT_STATE.md), [Data Model](DATA_MODEL.md), and the [Reference Table Runbook](PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md).

## Phase 2 — Core Recruitment App

- **Objective:** Support candidate, calling, queue, status, and interview outcome operations.
- **Scope:** Model-driven app and core workflows on approved schema.
- **Dependencies:** Phase 1 acceptance, validated field/outcome definitions, BSO access model.
- **Deliverables:** Candidate queues/details, call logs, status history, controlled interview results, admin/reference capability as approved.
- **Acceptance:** BSO can complete authorized core tasks; transitions enforce rules; history and negative authorization cases pass.
- **Validation:** Unit/integration/UAT/accessibility and authorization tests.
- **Risks:** Unvalidated SLA/KPI and detailed business rules.
- **Status:** Phase 2C is closed by the 21 October 2026 owner-approved adoption of existing AppModule `srapp` (ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`) in `os_sr_bso_rs_support`; no AppModule Create, rename, or recreation occurred. `srapp` supersedes the old `os_srapp` proposal for this app only. Phase 2D-P completed local script/test preparation and a GET-only DryRun; it reconfirmed Active/Unpublished state, the package-level `AppModuleSiteMap.SiteMapUniqueName=srapp` binding, no direct appmodulecomponent rows, and typed component keys from `$metadata`. The AppModule Publisher lookup and type 10091 identity remain unknown. Runtime AddAppComponents acceptance and Site Map PATCH draft-layer behavior remain untested; Phase 2D execution readiness is **BLOCKED** and no Apply is authorized.

## Phase 3 — Email and Scheduling

- **Objective:** Deliver controlled, auditable email and interview scheduling.
- **Scope:** Approved templates/dispatch and online/offline availability, calendar/Teams event lifecycle.
- **Dependencies:** Verified BSO connector identity, Outlook/calendar permissions, TA/room test accounts, DLP and provider semantics.
- **Deliverables:** Idempotent dispatch and booking contracts, reconciliation/monitoring, audit.
- **Acceptance:** Correct sender/organizer and recipients; availability fails closed and rechecks; duplicate/uncertain outcomes handled safely.
- **Validation:** Synthetic recipient/calendar tests, concurrency, failure injection, reconciliation, identity negative tests.
- **Risks:** Connector identity, external race conditions, uncertain outcomes.
- **Status:** Planned; not started.

## Phase 4 — CV, OCR and LEGO Careers

- **Objective:** Provide controlled CV prerequisites, optional OCR, and Vietnam posting sync/matching.
- **Scope:** CV URL validation; physical SharePoint storage only if approved; LEGO proxy integration; OCR only if approved.
- **Dependencies:** Data/privacy/retention decisions, API contract/access, DLP, licensing/capacity and accuracy review.
- **Deliverables:** Approved CV handling, idempotent career sync/manual resolution, optional OCR with human fallback.
- **Acceptance:** Correct Vietnam-only visibility/matching; partial sync safe; CV access controlled; OCR errors/confidence handled.
- **Validation:** Contract, privacy/access, partial failure, duplicate, and synthetic-document tests.
- **Risks:** API changes/access, sensitive documents, capacity/accuracy.
- **Status:** Planned; not started.

## Phase 5 — Operations, Reporting and Hardening

- **Objective:** Prepare supportable operations and security/performance posture.
- **Scope:** Monitoring, reporting, operational controls, accessibility, performance, resilience, retention.
- **Dependencies:** Prior feature stability; operations/security ownership; Power BI decision if applicable.
- **Deliverables:** Runbooks, alerts, dashboards/reports, hardening evidence.
- **Acceptance:** Operational owners can detect/respond to failures; least privilege, privacy, capacity, and recovery reviewed.
- **Validation:** Security, load/performance, recovery, monitoring, accessibility, and UAT regression.
- **Risks:** Unclear operational ownership and optional-service scope.
- **Status:** Planned; not started.

## Phase 6 — Migration, UAT and Production Cutover

- **Objective:** Reconcile approved ATSugg data and transition with acceptance and rollback.
- **Scope:** Staged migration, user acceptance, controlled cutover, ATSugg preservation until retirement criteria met.
- **Dependencies:** Source inventory/live access approval, mappings, identity map, retention/legal review, production environment and change approval.
- **Deliverables:** Rehearsed migration, reconciliation evidence, signed UAT, cutover and rollback plan, eventual retirement decision.
- **Acceptance:** Agreed required records/relationships reconcile, exceptions approved, business signs off, rollback viable, production approvals recorded.
- **Validation:** Test migration, count/field/history reconciliation, smoke tests, rollback rehearsal.
- **Risks:** Source data quality, audit gaps, delta/freeze window, rollback divergence.
- **Status:** Planned; not started.
