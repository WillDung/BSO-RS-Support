# Architecture

## Current R4O server-registration classifier

The prior `OTHER_PROTECTED_WRITE` result was evidence against runtime-shape inference, not evidence that the action/write allowlist was missing a CreateCandidate pair. The current source derives a table-bound protected write from `IPluginExecutionContext.OwningExtension` and the read-only `sdkmessageprocessingstep` -> handler type -> assembly -> existing package -> SDK message/filter metadata chain. It requires the exact active package-backed `os_sr_cact.ProtectCandidateCore` implementation and maps only the six explicitly supported message/entity pairs. Associate/Disassociate use their existing relationship guard; exact unsupported registrations fail closed. Runtime MessageName and PrimaryEntityName only cross-check the resolved registration. Verified API ancestor/action trust remains a separate required authorization and is unchanged. The 50/50 inventory was verified before and after the single existing-package update (6 mapped, 42 fail-closed unsupported, 2 relationship; no unresolved/contradictory rows). One CreateCandidate then failed with `UNSUPPORTED_GUARD_REGISTRATION`; the exact internal registration check is not localized, no matrix ran, and runtime acceptance is not established. Full evidence is in the [Phase 3D report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

## Candidate Core verified-ancestor trust correction

**Prior R4O runtime result:** `CANDIDATE_CORE_WRITE_CONTEXT_FAILURE_UNRESOLVED`. The bounded diagnostic returned only `CREATE_CANDIDATE:OTHER_PROTECTED_WRITE` at Candidate Create; no exact supported pair defect was established, so no second correction or runtime matrix followed. The current source-level registration classifier is documented above; the later single CreateCandidate was rejected as `UNSUPPORTED_GUARD_REGISTRATION`, so runtime acceptance remains unestablished. See [Current State](CURRENT_STATE.md).

At the historical R4O checkpoint, the [ActionType/protected-write contract](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md) allowed only the then-implemented Candidate/Call/History/Receipt mutations; the scheduling/result/reschedule actions remained fail-closed. This paragraph records that historical runtime state. Current local Phase 5A source now supports Pass/Fail result persistence through a fixed mutation matrix; scheduling, reschedule, and cancellation remain fail-closed pending trusted availability/calendar evidence. See [Current State](CURRENT_STATE.md). The R4O registration classifier changes only historical child-write identification, not the current caller/SYSTEM service boundary or its mutation matrix. Its one runtime CreateCandidate rejection is recorded above; no live runtime acceptance is established.

The owner-approved trust contract supersedes required cross-pipeline SharedVariables authorization following live `MARKER_MISSING` evidence. Protected child writes require the approved Custom API ancestor semantics plus read-only validation of server-owned `OwningExtension` through processing step, handler type, assembly and existing unsigned package. Markers are non-authoritative; direct callers cannot supply the execution registration. The calling-user validation, bounded positive cache, fail-closed behavior, ParentContext platform caveat and matching-guard legacy rollback requirement are specified in the [Security Model](SECURITY_MODEL.md). Deployment and runtime verification are recorded separately in the [Phase 3D runtime report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md); source implementation is not itself live acceptance.

## Historical target-architecture baseline

The older provisioning/readiness statements below are historical and superseded for Candidate Core by [Current State](CURRENT_STATE.md) and the latest [runtime report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md). The verified-ancestor package is deployed, but its acceptance call failed with `UNSUPPORTED_CORE_WRITE_CONTEXT`; the matrix did not run.

**Status:** Proposed target architecture, based on the draft blueprint. The four reference tables and unmanaged Solution are verified. The owner-adopted AppModule `srapp` (ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`) was separately composed and published as the complete 13-component reference-administration app; Phase 2D.4F accepted its UI with record-form tests deferred because no safe row existed. The app-only `srapp` name supersedes `os_srapp`; normal Dataverse table naming remains `os_sr_*`. Candidate-core owner decisions are now approved and documented, but Candidate schema and business operations remain unprovisioned proposals; Phase 3A readiness is blocked by external audit and API privilege prerequisites. See [Current State](CURRENT_STATE.md) and the [Phase 3A.2 report](PHASE_3A2_CANDIDATE_CORE_DECISION_APPLICATION.md).

## Logical components

| Concern | Target component | Boundary / status |
|---|---|---|
| Interactive operations | Power Apps Model-driven App | Existing AppModule `srapp` is published and verified with the four approved reference-table pages. No Candidate workflow is included. `os_srapp` was a superseded name proposal. Historical type-10091 identity remains unknown and is not treated as the Site Map. See [Model-driven App Manifest](MODEL_DRIVEN_APP_MANIFEST.md) and [Automation Runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md). |
| Complex interaction | Power Apps Custom Pages | Use only when justified; proposed |
| Authoritative data | Microsoft Dataverse | Sole production source for candidate workflow/business state; four approved reference tables are verified. Candidate core decisions are approved; its schema remains unprovisioned pending external audit/security gates. |
| Critical business operations | Dataverse Custom APIs and synchronous plug-ins | Proposed enforcement for critical transitions |
| Orchestration | Power Automate Cloud Flows | Integrations and asynchronous work; must call approved business operations |
| Mail and calendar | Microsoft 365 Outlook/Teams | Identity and permission model requires verification |
| Documents | SharePoint | Approved document storage, not candidate database; CV binary storage unresolved |
| Careers data | LEGO official careers proxy API | Intended source; contract/access unverified |
| Identity | Microsoft Entra ID | Authentication target; exact roles and tenant config unverified |
| ALM | Power Platform Solutions | Managed downstream deployment target; environments/pipeline unverified |
| Optional capabilities | AI Builder OCR, Power BI | Conditional on approval, privacy, capacity, and need |

## Proposed Dataverse schema boundary

The proposed table inventory is grouped into reference, candidate/history, interview/communication, and integration areas in [Data Model](DATA_MODEL.md). Four approved reference tables are verified. Candidate, Call Log, and Candidate Status History are unprovisioned; their product decisions are approved, but Phase 3A remains `BLOCKED_EXTERNAL_AUDIT_AND_API_PRIVILEGE_PREREQUISITES`. Complete proposed columns, ownership, keys, relationships, cascade rules, audit, security, and migration mappings are in [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md) and the [Phase 3A design report](PHASE_3A_CANDIDATE_CORE_DESIGN.md). No Candidate role, Custom API, plug-in, or flow is asserted implemented.

## Interaction and data flow

The UI requests a business action. Dataverse validates and commits critical candidate state and history through an approved server-side operation. Flows may orchestrate external side effects such as email/calendar calls, but do not bypass transition rules. External operations require correlation, idempotency where possible, explicit outcome states, and reconciliation for uncertain results. Dataverse remains business authority; SharePoint holds approved document binaries only.

## Model-driven App composition

The published `srapp` reference app contains the approved administration/reference surface for TA Directory, Positions, Candidate Sources, and Locations. Phase 2D.4F confirmed the single `Settings` Area / `Administration` group semantics and the four reference pages/views. Candidate workflow navigation is intentionally absent. The Phase 2D publication authorization is consumed; do not alter or republish the app in Phase 3A. See [Current State](CURRENT_STATE.md) and the [model-driven app automation runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md).

## Trust boundaries

Entra authentication, Dataverse role/row/field authorization, and Microsoft 365 connector identity are distinct. A BSO's app authorization does not prove their connector sends as the same identity. Verify sender and organizer identity before rollout. External calendars and email providers cannot be assumed to participate in Dataverse transactions.

## Architecture decisions still open

Candidate Core product decisions are owner-approved. Organization-level audit governance and the least-privilege Custom API execution privilege model remain external readiness gates; Choice allocation and AutoNumber support require fresh metadata preflight. Later schema, connector identity, calendar reconciliation, LEGO sync transport, CV file strategy, and optional services remain open for their respective phases. The selected naming strategy uses Publisher Prefix `os` plus namespace segment `sr_`; final technical names begin `os_sr_`. See [Security Model](SECURITY_MODEL.md), [Integration Design](INTEGRATION_DESIGN.md), [ALM Deployment](ALM_DEPLOYMENT.md), and [Product Decisions](PRODUCT_DECISIONS.md).
