# Implementation Plan

Phase status is factual as of 23 October 2026. Phase 0 foundation and Phase 1B Publisher/Solution setup are complete. The approved reference tables `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc` are verified. Phase 2D reference-app composition and publication are complete with the accepted deferred form-record-test caveat. Phase 3A owner product decisions are approved and applied to the deterministic proposal; provisioning readiness is **`BLOCKED_EXTERNAL_AUDIT_AND_API_PRIVILEGE_PREREQUISITES`**. Candidate, Call Log, Candidate Status History, Choices, Custom API, and plug-in are not provisioned or deployed. See [Current State](CURRENT_STATE.md) and the [Phase 3A.2 report](PHASE_3A2_CANDIDATE_CORE_DECISION_APPLICATION.md).

The first Position Apply attempt on 20 October 2026 returned HTTP 401. This is historical and was followed by separately authorized reference-table operations; it is not the current table inventory. Its root cause remains unknown. See [Current State](CURRENT_STATE.md) and [Scripts](../scripts/README.md).

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
- **Scope:** Phase 1A/1B setup and the approved reference-table slices are complete. Candidate core schema, remaining domain tables, roles, and server-enforced operations require decision closure and separate authorization.
- **Dependencies:** Schema and security approval, ownership, keys, retention, call/visitor/result decisions, environment governance, connector identities, source mapping, and ALM approach.
- **Deliverables:** [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md); Publisher, unmanaged Solution, and four reference tables verified. Candidate core proposal is separately documented in [Phase 3A](PHASE_3A_CANDIDATE_CORE_DESIGN.md). No Candidate business records, Candidate API, or Candidate plug-in exists.
- **Acceptance:** Resolve design decisions; approve schema and security; verify keys/relationships/audit; then test permitted/blocked transitions and no duplicate status/history before implementation acceptance.
- **Validation:** Static logical-name/key/relationship review; read-only solution component check; executable Dataverse/API, authorization, concurrency, and audit tests only after a separately approved implementation.
- **Risks:** TA identity, child ownership/effective-access model, key value formats, field-level security vs keys, audit retention, external side effects, and legacy data semantics remain unresolved.
- **Status:** Publisher/Solution setup and the separately approved reference-table implementations are complete. Candidate-core product decisions are approved and the schema remains unprovisioned. Organization-level audit governance and least-privilege Candidate business-operation security remain unresolved readiness gates. See [Current State](CURRENT_STATE.md), [Data Model](DATA_MODEL.md), and the [Reference Table Runbook](PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md).

## Phase 2 — Core Recruitment App

- **Objective:** Support candidate, calling, queue, status, and interview outcome operations.
- **Scope:** Model-driven app and core workflows on approved schema.
- **Dependencies:** Phase 1 acceptance, validated field/outcome definitions, BSO access model.
- **Deliverables:** Candidate queues/details, call logs, status history, controlled interview results, admin/reference capability as approved.
- **Acceptance:** BSO can complete authorized core tasks; transitions enforce rules; history and negative authorization cases pass.
- **Validation:** Unit/integration/UAT/accessibility and authorization tests.
- **Risks:** Unvalidated SLA/KPI and detailed business rules.
- **Status:** Phase 2C adoption and Phase 2D reference-app build are complete. `srapp` is published with its accepted 13-component reference administration scope; Phase 2D.4F classified the UI `PUBLISHED_UI_ACCEPTED_WITH_DEFERRED_FORM_RECORD_TEST` and the build milestone `PHASE_2D_COMPLETE`. Candidate workflow is not in that app. See [Current State](CURRENT_STATE.md); earlier 2D subsections below are retained as execution history and superseded by the later 4E/4F closeout.

**Phase 2D.1 historical status — superseded by Phase 2D.2:** The fresh GET-only preflight found `App does not contain Site Map` and stopped without a write. The owner then explicitly authorized the Site Map-only association.

**Phase 2D.2 status — 22 October 2026:** The exact existing Site Map was the only component in one AddAppComponents POST (HTTP 204). GET-only reconciliation verified the Site Map association, unchanged Site Map XML, unchanged `srapp` identity and Active/Unpublished state, unchanged roles, and no unintended direct app components. Post-write ValidateApp no longer reports the Site Map error; one entity-reference warning remains. Outcome: **VERIFIED_SITEMAP_ASSOCIATED**. Counts: 75 recorded Dataverse Web API GET, one AddAppComponents POST, zero other POST, Site Map PATCH, PublishXml, publish, role change, and retry. No Phase 2D.3 table/form/view component was added.

**Phase 2D.3 status — 22 October 2026:** The dedicated flow now requires the exact approved Information Main forms and named public active views, exact Solution membership, the existing Site Map as the sole starting direct app component, and the approved role set. It will send one POST for 12 components, reconcile the 13-component app and intermediate validation, then issue at most one ETag-protected Site Map PATCH and perform final GET-only validation. The fresh guarded preflight stopped at `Verify PAC target`; all required process-scoped target variables and the expected-user guard were unavailable, so Dataverse `WhoAmI` and live metadata verification were not attempted. **Outcome: BLOCKED_BEFORE_WRITE; 0 Dataverse GET and 0 writes.** The live app remains at its last verified Phase 2D.2 state. The new synthetic suite passes 80 app-composition assertions; provisioning/recovery and readiness suites pass 550 and 11 assertions. See [Current State](CURRENT_STATE.md) and the [Model-driven App Automation Runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md).

## Phase 3A — Candidate Core Design & Provisioning Readiness

- **Objective:** Define the Candidate, Call Log, and Candidate Status History model and server-enforced transition contract; complete only the separately authorized Candidate-table metadata slice.
- **Scope:** The Candidate Status Choice, Candidate table, two alternate keys, and Position/Candidate Source/TA lookups are provisioned and reconciled. No Candidate business rows, Call Log/History tables, Call Outcome Choice, API/plugin deployment, app changes, publication, or role/access changes.
- **Dependencies:** Owner decisions are approved. Organization audit governance remains required before Candidate data; least-privilege Custom API execution/effective-access design remains required before API/plugin implementation. The Candidate Status Choice allocation/binding and AutoNumber metadata path are verified; Call Outcome option allocation is deferred.
- **Deliverables:** [Phase 3A design report](PHASE_3A_CANDIDATE_CORE_DESIGN.md), [synthetic metadata proposal/current-state manifest](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json), [Candidate-only provisioning report](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md), and [offline assertion harness](../tests/Phase3ACandidateCoreDesign.Tests.ps1).
- **Acceptance:** Candidate-only metadata has exact schema, keys, lookup targets, audit metadata, and Solution inclusion; full business-operation acceptance remains pending API/plugin implementation and tests.
- **Validation:** Offline proposal assertions, existing regression/readiness suites, and `git diff --check`. Runtime Dataverse/API/authorization/concurrency tests require a future implementation in an approved test environment.
- **Status:** Candidate-only schema is complete and GET-reconciled. Full Candidate Core remains **`BLOCKED_EXTERNAL_AUDIT_AND_API_PRIVILEGE_PREREQUISITES`**. The seven-write authorization is consumed; organization auditing is disabled, so no Candidate data may be created. No API/plugin has been deployed.

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
