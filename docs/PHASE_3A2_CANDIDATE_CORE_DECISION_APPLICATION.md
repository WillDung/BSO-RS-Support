# Phase 3A.2 — Candidate Core Decision Application & Readiness Report

**Date:** 23 October 2026  
**Scope:** Apply explicit owner decisions to the Phase 3A design and offline proposal only. No tenant connection, Dataverse reads/writes, provisioning, app/access changes, or Phase 2D work.  
**Final classification:** `BLOCKED_EXTERNAL_AUDIT_AND_API_PRIVILEGE_PREREQUISITES`

## 1. Executive Summary

The owner explicitly approved all eight Phase 3A.1 decision areas. The decisions are applied to the Candidate Core design, metadata proposal, workflow, security/privacy documentation, and offline assertions. No Candidate, Call Log, Candidate Status History, Choice, Custom API, or plug-in is provisioned or implemented.

The remaining blockers are external readiness prerequisites: the last documented environment assessment found organization-level auditing disabled and IT/Compliance audit governance unresolved; the least-privilege Custom API Execute privilege/effective-access design is not approved or tested. Choice allocation and Candidate AutoNumber support also require fresh guarded preflight before any future write.

## 2. Decision Authority and Status

**Owner-approved requirement:** the decisions below were explicitly supplied by the project owner on 23 October 2026. They supersede the corresponding unresolved Phase 3A / Phase 3A.1 items.

**Current implementation:** none of the Candidate Core metadata or operations exists as a result of this work. The manifest remains a synthetic proposal and is marked `PROPOSAL_NOT_AUTHORIZED`.

**Historical record:** the first Phase 3A.1 closure attempt accurately recorded that it had no owner-authored selections at that time. The later approval supersedes that report's “not recorded” items as current decisions; see [Phase 3A.1 closure report](PHASE_3A1_CANDIDATE_CORE_DECISION_CLOSURE.md).

## 3. Candidate Number

**Owner decision:** Accepted recommendation — server-generated, immutable, unique, and contains no personal information; users cannot edit it after creation.

**Applied proposal:** `os_sr_cand_cnum` is the Candidate primary name, proposed as Dataverse AutoNumber `CAND-{SEQNUM:8}` with a unique alternate key. Dataverse generation, write protection, uniqueness, and supported metadata creation must be verified before provisioning. The specific AutoNumber format is a technical proposal, not an additional owner product decision.

## 4. Call Outcome Taxonomy

**Owner-approved initial outcomes:** Answered, No Answer, and Call Back Requested.

| Outcome from Need Call Candidate | Call Log | Candidate status | Status History |
|---|---|---|---|
| Answered | Create | Change to Candidate Answered | Create exactly one row atomically |
| No Answer | Create | No change | No row |
| Call Back Requested | Create | No change | No row |

The proposal uses global Choice `os_sr_callout`; its numeric allocation remains subject to platform preflight.

## 5. Candidate Contact Requirements

**Owner-approved:** Candidate Name required; Email required; Phone optional. The schema proposal records these requirements at Candidate creation. Email is not an alternate key. In the initial slice, no column-level security is applied to Name, Email, or Phone; table/row access and audit requirements remain.

## 6. BSO Ownership

**Owner-approved:** Dataverse record `ownerid` is the responsible BSO. No duplicate Assigned BSO lookup is added. TA remains a separate interviewer/directory lookup and is not the Candidate owner by default.

**Proposed operation behavior:** Candidate creation sets Owner from the authenticated initiating BSO. Child record ownership must be assigned deliberately by the approved operation. No user, team, role, or sharing change is authorized here.

## 7. Reschedule Policy

**Owner-approved:** Reschedule from Round 1 Scheduled to Need Call Candidate requires a mandatory reason. Candidate Status History records actor, timestamp, CorrelationId, previous status, new status, and reason.

**Explicit deferral:** Calendar/event cancellation evidence and execution belong to the later scheduling phase. To preserve the canonical cancellation-attempt rule, the reschedule action must remain unavailable until that boundary can make and record the cancellation attempt. This design does not claim rescheduling is currently executable.

## 8. Privacy and Audit

**Owner-approved requirement:** Enable Dataverse table auditing for Candidate, Call Log, and Candidate Status History. Do not apply column-level security to Candidate Name, Email, or Phone in this initial slice unless later organizational policy requires it. Synthetic data only; never use real candidate data in source, fixtures, prompts, logs, reports, or provisioning evidence.

**External dependency:** The latest repository-recorded environment assessment found organization auditing disabled and configured retention of 30 days, which is not an approved retention policy. IT/Compliance must resolve organization-level audit activation, retention, access, legal-hold/DSR, and capacity ownership before auditing can be relied on. This task made no environment change.

## 9. Operation Identity and Idempotency

**Owner-approved:** Every state-changing Candidate business operation requires a caller-generated GUID CorrelationId. Duplicate execution for the same logical operation must not create duplicate Call Logs, Status History rows, or status transitions.

**Applied proposal:** CorrelationId is required by the server operation and is reused only for retries of the same logical operation. Proposed uniqueness is scoped through Candidate creation, Call Log, and Status History alternate keys; exact replays return the original result, while a reused correlation with changed intent is rejected. The authenticated initiating user supplies actor identity; clients cannot choose or impersonate the actor.

## 10. LEGO Career Dependency

**Owner-approved:** Defer the LEGO Career lookup from Candidate core. Candidate core includes Position. Linked LEGO Career validation is enforced later at the scheduling/booking boundary, not at Candidate creation.

**Applied proposal:** `os_sr_cand_lgcar` and the Candidate-to-LEGO-Career relationship are absent from the Phase 3A manifest. Future booking must still enforce the linked-career and CV prerequisites under the canonical rules.

## 11. Workflow and Operation Contract

The canonical six statuses remain unchanged. Candidate starts at Need Call Candidate with no fabricated initial History row. Answered, No Answer, and Call Back Requested follow the effects in Section 4. All valid state changes pass through proposed synchronous `os_sr_cact` server-side validation; expected-status and row-version checks, authenticated actor derivation, correlation idempotency, and atomic Candidate/Call/History effects remain required.

No scheduling, email, calendar calls, candidate-data operation, or production workflow was implemented. Reschedule remains deferred as specified in Section 7.

## 12. Schema Proposal and Provisioning Sequence

The updated synthetic manifest contains exactly three proposed tables (`os_sr_cand`, `os_sr_call`, `os_sr_csh`), the status and call-outcome Choices, and the `os_sr_cact` contract. Candidate has Position, Candidate Source, and TA lookups; no LEGO Career lookup. Table-audit flags are required for all three tables. GUID CorrelationId fields/keys support the approved idempotency contract.

The proposed order is: guarded environment/solution/publisher and value-allocation preflight; resolve audit governance and AutoNumber support; create/verify both Choices; create the three tables and columns with audit flags; create only approved existing-table relationships; create and verify alternate keys; verify Solution membership; implement the Custom API/plug-in in a separately bounded phase after security/atomicity review. Each future metadata or code operation still requires separate explicit authorization.

## 13. Remaining Readiness Gates

### Blocking

1. **Organization-level audit governance:** last recorded environment state is auditing disabled. IT/Compliance must resolve activation and retention/access/capacity governance before table auditing can be relied on.
2. **Custom API least-privilege execution model:** the Execute privilege and effective-access design must be approved and validated while preserving the initiating BSO identity.

### Required fresh preflight before any future write

- Verify publisher option-value allocation for both Choices.
- Verify the supported Candidate AutoNumber metadata path and immutable/unique behavior.
- Verify exact environment, active identity, solution, publisher, and existing lookup targets using the approved guarded workflow.

The deferred calendar cancellation boundary is a later scheduling implementation dependency, not an unresolved Candidate Core product decision.

## 14. Manifest Fingerprint

The revised manifest SHA-256 is `8e035cc64451817efb8342fec245df2aa5e943eb3bd81fe3d5393ee9185d2e08`. It identifies the local JSON proposal bytes only; it is not a Dataverse request payload hash or provisioning authorization.

## 15. Offline Validation

`& .\tests\Phase3ACandidateCoreDesign.Tests.ps1` passed **33 synthetic assertions** and confirmed no authentication, network, PAC, or tenant calls. The manifest parsed as JSON with exactly three proposed tables, five relationships, three call-outcome rules, and zero unresolved owner decisions. Its SHA-256 (`8e035cc64451817efb8342fec245df2aa5e943eb3bd81fe3d5393ee9185d2e08`) matched both design reports. `git diff --check` passed, and relative Markdown links resolved in all 14 changed Markdown files. These local checks validate proposal consistency only; they do not prove Dataverse behavior, option allocation, effective access, audit activation, or plug-in transaction semantics.

## 16. No-Write Proof

| Operation | Count |
|---|---:|
| Tenant connections | 0 |
| Dataverse reads / metadata requests | 0 |
| Dataverse metadata or business-data writes | 0 |
| Custom API / plug-in deployment | 0 |
| PublishXml / PublishAllXml | 0 / 0 |
| App, Site Map, or component changes | 0 |
| User, team, role, or access changes | 0 |
| Audit/environment/DLP changes | 0 |
| Retries | 0 |
| Commits / pushes | 0 / 0 |

## 17. Phase 2D Regression Boundary

The published `srapp` and its accepted Phase 2D state were not modified. No Phase 2D navigation, app composition, publication, access, or test-data work was performed.

## 18. Final Classification

**`BLOCKED_EXTERNAL_AUDIT_AND_API_PRIVILEGE_PREREQUISITES`**

All owner product decisions are recorded and applied. Candidate Core provisioning readiness is not established because audit governance and least-privilege Custom API execution remain unresolved; required value-allocation and AutoNumber checks also need fresh preflight.

## 19. Exact Recommended Next Task

Obtain IT/Compliance resolution for organization-level audit activation, retention, access, and capacity, and obtain Security-owner approval for the least-privilege Custom API Execute/effective-access model. Then perform a separately authorized, guarded read-only preflight for environment/solution/publisher, Choice allocation, and AutoNumber support. Do not provision until those gates pass and separate bounded write authorization is provided.

## 20. AI HANDOVER

- Owner decisions from 23 October 2026 are authoritative and supersede the “not recorded” Phase 3A.1 closure state.
- Current classification is `BLOCKED_EXTERNAL_AUDIT_AND_API_PRIVILEGE_PREREQUISITES`, not `BLOCKED_PRODUCT_DECISION`.
- Candidate Core remains an unprovisioned synthetic proposal; Phase 2D remains unchanged.
- Candidate Number is server-generated/nonpersonal/immutable/unique; Name and Email are required; Phone is optional; Dataverse Owner is responsible BSO.
- Initial outcomes are Answered (Call + transition + History atomically), No Answer (Call only), and Call Back Requested (Call only).
- Reschedule reason/history requirements are approved, but actual reschedule execution is deferred until the scheduling phase supports cancellation attempts/evidence.
- Table auditing for Candidate, Call Log, and Candidate Status History is required. No column-level security applies to Candidate Name/Email/Phone in the initial slice. Do not change tenant settings under this task.
- Caller-generated GUID CorrelationId is required for every state-changing Candidate operation and reused only for retries of that logical operation.
- Candidate core includes Position and excludes the LEGO Career lookup; booking-boundary validation remains required later.
- No tenant calls, writes, publication, app/access changes, retries, commit, or push occurred.
