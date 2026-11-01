# Implementation Plan

**Current implementation phase:** Phase 5B BSO security acceptance is complete in DEV, as detailed in [Current State](CURRENT_STATE.md). The active next phase is the bounded LMV BI DEV managed-artifact/Test rehearsal; this is not Production deployment authorization. Owner authorization includes the current verified connected deployment identity and existing checkpoint/recovery procedure. Target, baseline, source, permission, and external TEST configuration evidence were verified. The rehearsal is stopped before bootstrap import at `TEST_MANAGED_ARTIFACT_BOOTSTRAP_CLEANUP_BLOCKED:unmanaged solution deletion leaves customizations in the Default Solution, while same-environment managed import is unsupported; no approved BSO-only component teardown restores the pre-rehearsal baseline`. Production audit/privacy/DLP, migration, integration, support, and real-data decisions remain separate Production gates. No real data is permitted.

**Historical Phase 3D-R4O result, 26 October 2026:** `CREATECANDIDATE_RUNTIME_FAILURE` / `UNSUPPORTED_GUARD_REGISTRATION`. One update of the existing unsigned package was reconciled; one synthetic CreateCandidate was rejected with `DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_GUARD_REGISTRATION:CC_CREATE_CANDIDATE:0x80040265`; retries 0. The registration inventory, package topology, API/schema, trace Off and no-Profiler gates passed before/after package update. No matrix, second package update/call, or additional backend diagnostic ran; post-call counts were not re-read after the stop. Phase 3D was not runtime accepted or complete. The exact inventory and artifact/test evidence are in [Current State](CURRENT_STATE.md), [Architecture](ARCHITECTURE.md), [Security Model](SECURITY_MODEL.md) and the [runtime report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

**Prior verified-ancestor runtime disposition, 26 October 2026:** `CANDIDATE_CORE_TRUST_MODEL_FAILURE:UNSUPPORTED_CORE_WRITE_CONTEXT`. Owner approval replaced required SharedVariables marker trust with verified server-owned ancestor/OwningExtension registration. That attempt preceded the R4O server-registration classifier and its later `UNSUPPORTED_GUARD_REGISTRATION` runtime rejection. It remains historical; do not treat its old next-diagnostic instructions as current. See [Current State](CURRENT_STATE.md), [Security Model](SECURITY_MODEL.md) and the [runtime report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

**Earlier Phase 3D-R4M baseline, 26 October 2026 (superseded by the current R4O result above):** Candidate Core storage and the owner-approved minimal receipt infrastructure are provisioned/reconciled. Phase 3C API/plugin metadata is deployed. Organization auditing remains disabled and unchanged; bounded synthetic Candidate Core acceptance is permitted while audit activation remains an external prerequisite before real rollout. R4M's CreateCandidate dispatch returned the historical R4L `CALLER_MARKER` diagnostic. These older package and runtime results are retained in the [Phase 3D report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md); they are not current status or current authorization. No commit or push.

**Historical Phase 3D-R4M baseline (superseded by the current R4O status above):** Phase 0 foundation, Publisher/Solution setup, reference-table provisioning, Phase 2D app publication, and Phase 3A/3C Candidate Core storage/API metadata were reported complete or reconciled at that checkpoint. The R4M runtime failure and Profiler next-step notes elsewhere in this plan are historical and do not authorize further action. Current Phase 3D status is in [Current State](CURRENT_STATE.md) and the [runtime report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

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
- **Scope:** Candidate, Call Log, Candidate Status History, Operation Receipt, both global Choices, and the approved API/plugin metadata are provisioned and reconciled. Phase 3D is limited to at most one synthetic Candidate under a consumed one-shot authorization; no live operation is claimed.
- **Dependencies:** Organization audit governance remains required for production rollout; it is not a runtime rejection. Least-privilege caller-role/effective-access acceptance is deferred to Candidate UI + Security. Trusted scheduler, result, and cancellation evidence remain future dependencies. Any further runtime acceptance requires new owner authorization because the prior one-shot lock is consumed.
- **Deliverables:** [Phase 3A design report](PHASE_3A_CANDIDATE_CORE_DESIGN.md), [synthetic metadata proposal/current-state manifest](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json), [Candidate-only provisioning report](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md), and [offline assertion harness](../tests/Phase3ACandidateCoreDesign.Tests.ps1).
- **Acceptance:** Candidate Core metadata is GET-reconciled. Live transaction, replay, conflict, and supported-action behavior remains unverified. Scheduler/result/reschedule fail-closed behavior is an expected acceptance condition, not a request to enable those actions.
- **Validation:** Offline assertion suites; guarded deployment reconciliation; count-only live reads. Do not rerun the consumed runtime Apply path. Any further live test requires new owner authorization and an exact dispatch journal/outcome review.
- **Status:** Candidate Core storage and API/plugin metadata are deployed and GET-reconciled. Phase 3D is **`UNCERTAIN_WRITE_OUTCOME`**: four fresh counts are zero, but the dispatch count associated with the pre-existing one-shot lock cannot be established. Organization audit activation remains an external governance/release prerequisite; no runtime retry or new data write is authorized by this status update.

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
