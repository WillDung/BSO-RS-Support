# Phase 3A — Candidate Core Domain Design & Provisioning Readiness Report

**As of:** 23 October 2026  
**Final classification:** `BLOCKED_PRODUCT_DECISION`  
**Phase:** Design/readiness only. No schema write, API/plugin implementation, publication, app change, or business-record operation is authorized by this report.

**Phase 3A.1 follow-up:** The requested owner-decision closure did not receive owner-authored selections. No proposal item is treated as approved; schema and manifest are unchanged. See the [Phase 3A.1 decision closure report](PHASE_3A1_CANDIDATE_CORE_DECISION_CLOSURE.md).

## 1. Executive Summary

The existing repository proposal and the Phase 3A review support a consistent, server-enforced domain shape for Candidate, Call Log, and Candidate Status History. The canonical six-state workflow and naming family are already specified. A deterministic proposal snapshot is in [the metadata plan](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json).

Provisioning readiness is **blocked** because decisions that change the initial schema or action contract remain open: Candidate Number source/format, call outcome taxonomy, create-time contact requiredness, Candidate owner/BSO semantics, reschedule evidence/reason requirements, sensitive-field/audit policy, and the unprovisioned LEGO Career lookup target. These are not silently decided here. No Candidate business rows or tenant metadata were queried or written.

The proposal uses a global Choice, `os_sr_candstat`, and one synchronous server operation, `os_sr_cact`, with a main-operation plug-in. Direct status editing is blocked. Candidate state, any applicable Call Log, and exactly one Status History row must commit atomically. Booking, calendar cancellation, interview result capture, email, and integrations remain out of this phase.

## 2. Repository / Phase Baseline

- Repository: `BSO-RS-Support`; branch `main`.
- HEAD: `0b8f3aa8fe3bfdbc6dea40c13b97a517e31cabfd`.
- `origin/main`: `0b8f3aa8fe3bfdbc6dea40c13b97a517e31cabfd`.
- Initial worktree: clean; no pre-existing user changes were present.
- Phase 2D reference-app milestone: `PHASE_2D_COMPLETE`. Published `srapp` remains the reference-administration app only; this work does not alter it.
- Current verified app pages remain TA Directory, Positions, Candidate Sources, and Locations. No Candidate, Call Log, or Candidate Status History table is represented as deployed.
- The exact approved reference tables (`os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, `os_sr_loc`) exist; `os_sr_lgcar` is a proposed, not Phase 2D-verified, lookup target.
- Project table prefix contract is `os_sr_*`; solution name is `os_sr_bso_rs_support`.
- No ATSugg source schema or live candidate data was inspected.
- At closeout, HEAD and `origin/main` remain `0b8f3aa8fe3bfdbc6dea40c13b97a517e31cabfd`. The worktree contains nine modified tracked documentation/test files and three new in-scope files listed in Section 23; no commit or push was made.

The pre-existing Phase 2D documentation edits were already committed before this phase. This work began from a clean repository state and does not restore, stash, switch, pull, rebase, commit, or push.

## 3. Candidate Table Design

**Proposed table:** `os_sr_cand` / Candidate; `UserOwned`. It is not provisioned.

| Proposed column | Type / limit | Classification | Requiredness / rule |
|---|---|---|---|
| `os_sr_cand_cnum` — Candidate Number | Text, 100; primary name | Required | Unique, stable internal identifier and proposed alternate key. Source, generation, format, confidentiality, and permitted characters remain unresolved. |
| `os_sr_cand_nm` — Candidate Name | Text, 200 | Required | Personal information; confirm create-time requirement and field security. |
| `os_sr_cand_eml` — Candidate Email | Email text, 254 | Recommended | Optional at creation in the existing proposal; required before booking under current rules. Not unique and not an alternate key. |
| `os_sr_cand_phn` — Candidate Phone | Phone text, 50 | Optional / conditional | Require only if the approved first-slice contact operation uses phone; normalization and contact-channel policy are unresolved. |
| `os_sr_cand_pos` — Position | Lookup to `os_sr_pos` | Recommended | Optional at creation in the current proposal; do not infer title uniqueness. |
| `os_sr_cand_csrc` — Candidate Source | Lookup to `os_sr_csrc` | Recommended | Optional at creation in the current proposal; retain historical source meaning. |
| `os_sr_cand_ta` — Assigned TA | Lookup to `os_sr_ta` | Conditional | Required before booking; TA remains an interviewer/directory contact, not an approval role. |
| `os_sr_cand_lgcar` — LEGO Career | Lookup to `os_sr_lgcar` | Conditional | Required before booking under current rules. The target table is a dependency outside the verified Phase 2D table inventory. |
| `os_sr_cand_cvurl` — Candidate CV URL | URL text, 2,000 | Conditional, sensitive | Required before booking under current rules; access/host/retention and field-security policy need approval. |
| `os_sr_cand_stat` — Candidate Workflow Status | Global Choice `os_sr_candstat` | Required | Default `Need Call Candidate`; no direct interactive editing. |
| `ownerid` | Dataverse system lookup | System | Proposed BSO/approved-team boundary; who assigns, transfers, and shares ownership is unresolved. |
| `createdon`, `createdby`, `modifiedon`, `modifiedby` | Dataverse system columns | System | Do not duplicate as custom columns. |
| `versionnumber` | Dataverse row version | System | Use for optimistic concurrency if enabled and verified; do not add a custom workflow version without a demonstrated need. |

Do not put candidate name, email, phone, CV URL, salary, interview result, or free-form notes in the primary name or technical identifiers. Email is informational/operational, not a globally unique identity key.

## 4. Candidate Status Design

**Representation:** proposed global Dataverse Choice `os_sr_candstat`, shared by Candidate and Status History. The labels are fixed requirements; numeric values below are deterministic proposals, not live metadata evidence.

| Proposed integer | Label | Default |
|---:|---|---|
| 100010000 | Need Call Candidate | Yes |
| 100010001 | Candidate Answered | No |
| 100010002 | Waiting Manual Scheduling | No |
| 100010003 | Round 1 Scheduled | No |
| 100010004 | Offer Extended | No |
| 100010005 | Candidate Failed | No |

These values follow the `10001` publisher option-value prefix noted by the existing schema proposal; verify allocation and collisions before any future create. Treat assigned numeric values as immutable after approval/deployment. Application code should use these stable values, not compare localized labels. `statecode/statuscode` remain separate platform Active/Inactive fields.

Block direct UI, Web API, and Flow status changes. Only the approved Dataverse business operation may transition state. Initial creation at the default status is not a transition and does not create a fabricated history row.

## 5. Call Log Design

**Proposed table:** `os_sr_call` / Call Log; `UserOwned`; append-only through the approved action.

| Proposed column | Type / limit | Requiredness / rule |
|---|---|---|
| `os_sr_call_ref` — Call Reference | Autonumber Text, `CALL-{SEQNUM:8}` | System-generated nonpersonal primary name; sequence gaps are acceptable. |
| `os_sr_call_cand` — Candidate | Lookup to `os_sr_cand` | Required; parent deletion restricted. |
| `os_sr_call_out` — Call Outcome | Text, 100 in the existing proposal | Required, but the controlled outcome taxonomy is an open product decision. Do not parse arbitrary text as an instruction. |
| `os_sr_call_ctat` — Contacted At | Date/Time, User Local | Required business-event time; distinct from record creation time. |
| `os_sr_call_ctby` — Contacted By | Lookup to `systemuser` | Required; resolve from authenticated initiating identity, not a client-supplied user or fixed Flow owner. |
| `os_sr_call_nts` — Notes | Multiline Text, 4,000 | Optional; minimize and restrict any personal/sensitive detail. |
| `os_sr_call_corid` — Correlation ID | Text, 100 | Conditional; nonsecret operation correlation only. |
| `os_sr_call_actkey` — Action Idempotency Key | Text, 100 | Required for operation-created rows; opaque URL-safe token, not a credential. |

Normal BSO application behavior: Read only; no direct Create/Update/Delete. A validated server action appends a row. Whether an administrator may correct/delete under a separately audited retention process is not decided here. Candidate hard-delete must be restricted while child records exist; deactivation must not delete call evidence. A unique alternate key on Candidate + Action Idempotency Key prevents duplicate operation submissions.

Only the workflow-supported answered outcome is known to cause the `Need Call Candidate` → `Candidate Answered` transition. Other outcome values and whether all unsuccessful attempts are loggable remain unresolved; do not invent values such as Busy, No Answer, or Voicemail.

## 6. Candidate Status History Design

**Proposed table:** `os_sr_csh` / Candidate Status History; `UserOwned`; application-immutable transition evidence.

| Proposed column | Type / limit | Requiredness / rule |
|---|---|---|
| `os_sr_csh_ref` — Transition Reference | Autonumber Text, `HIST-{SEQNUM:8}` | System-generated nonpersonal primary name. |
| `os_sr_csh_cand` — Candidate | Lookup to `os_sr_cand` | Required; delete restricted. |
| `os_sr_csh_prevstat` — Previous Status | Global Choice `os_sr_candstat` | Required. |
| `os_sr_csh_newstat` — New Status | Global Choice `os_sr_candstat` | Required; must be an allowed transition and differ from previous. |
| `os_sr_csh_actr` — Actor | Lookup to `systemuser` | Required; derived from authenticated initiating identity. |
| `os_sr_csh_chg` — Changed At | Date/Time, User Local | Required; server-generated UTC transition time. |
| `os_sr_csh_rsn` — Reason | Multiline Text, 1,000 | Conditional; required only under an owner-approved action/reason policy. |
| `os_sr_csh_corid` — Correlation ID | Text, 100 | Conditional; links external evidence without storing raw payloads. |
| `os_sr_csh_cact` — Candidate Action | Text, 50 | Required, operation-controlled allowlisted action name. |
| `os_sr_csh_actkey` — Transition Idempotency Key | Text, 100 | Required for operation-created transitions. |

Normal application access is Read only. Direct user Create/Update/Delete must be denied or blocked by a server-enforced write guard; only the trusted operation creates rows. `Delete=Restrict` and no cascade delete/assign/share/reparent. Ownership should be set by the server operation according to the approved Candidate owner policy; a lookup does not itself grant row access.

The purpose-built history is the business transition record, not a substitute for Dataverse auditing. Audit settings and retention remain subject to IT/Compliance approval.

## 7. Relationship Model

| Parent → child | Relationship / lookup | Requiredness | Delete / cascade |
|---|---|---|---|
| Candidate → Call Log | `os_sr_cand_call` / `os_sr_call_cand` | Required | Restrict delete; no cascade on assign/share/reparent. |
| Candidate → Candidate Status History | `os_sr_cand_csh` / `os_sr_csh_cand` | Required | Restrict delete; preserve history. |
| Position → Candidate | `os_sr_pos_cand` / `os_sr_cand_pos` | Candidate lookup proposed optional | Restrict; deactivate reference, do not delete history. |
| Candidate Source → Candidate | `os_sr_csrc_cand` / `os_sr_cand_csrc` | Candidate lookup proposed optional | Restrict; preserve historical source. |
| TA Directory → Candidate | `os_sr_ta_cand` / `os_sr_cand_ta` | Conditional, required before booking | Restrict; TA is not an app approver. |
| LEGO Career → Candidate | `os_sr_lgcar_cand` / `os_sr_cand_lgcar` | Conditional, required before booking | Restrict; target table is an unresolved provisioning dependency. |

Candidate ownership is the security boundary; child records do not inherit access by lookup. The operation must set child ownership deliberately. No relationship cascade should delete call or status-history evidence when a Candidate or reference row is deactivated. Hard-delete policy, transfer/share behavior, and BSO-versus-team ownership require approval.

## 8. Transition Matrix

| Current status | Action / qualifying result | Next status | Allowed? | Guard |
|---|---|---|---|---|
| Need Call Candidate | `RecordCall`, approved outcome says candidate answered | Candidate Answered | Yes | Same transaction appends Call Log and one History row. |
| Candidate Answered | `ProceedToScheduling` | Waiting Manual Scheduling | Yes | Required CV URL and valid linked LEGO Career are present under current rules. |
| Waiting Manual Scheduling | `MarkRound1Scheduled` | Round 1 Scheduled | Yes | Only after a future scheduler reports a verified successful booking. |
| Round 1 Scheduled | `RecordPass` | Offer Extended | Yes | Requires future authorized Pass result evidence. |
| Round 1 Scheduled | `RecordFail` | Candidate Failed | Yes | Requires future authorized Fail result evidence. |
| Round 1 Scheduled | `RequestReschedule` | Need Call Candidate | Yes, conditionally | Requires verified cancellation/reconciliation evidence and applicable reason; no calendar call in Phase 3A. |
| Any status | Same status / no-op “transition” | Same status | No | No transition or duplicate history row. |
| Need Call Candidate | Skip directly to Waiting Manual Scheduling or Round 1 Scheduled | Any later status | No | Reject skipped states. |
| Candidate Answered | Return directly to Need Call Candidate | Need Call Candidate | No | Reschedule path is only from Round 1 Scheduled. |
| Waiting Manual Scheduling | Pass / Fail / Offer Extended / Candidate Failed | Terminal status | No | No result transition before a Round 1 Scheduled state and valid result evidence. |
| Offer Extended | Arbitrary rollback | Any earlier status | No | Terminal in this workflow. |
| Candidate Failed | Arbitrary rollback | Any earlier status | No | Terminal in this workflow. |
| Any status | Legacy Draft Created / BSO Reviewing / Sent to TA / TA Approval | Any | No | Deprecated stages are prohibited. |
| Any status | Unknown action, stale status, missing evidence, unauthorized caller | Any | No | Fail closed with no partial writes. |

The six statuses and canonical path are confirmed. Detailed outcome values, evidence payloads, and reason policy remain proposed/open as stated above.

## 9. Call Action Contract

Proposed single entry point: `os_sr_cact` (“Apply Candidate Action”). For `RecordCall`, it validates the authenticated BSO, Candidate ID, current expected status, idempotency token, contacted timestamp, and an approved outcome.

- If the Candidate is `Need Call Candidate` and the approved outcome is “candidate answered,” atomically append one Call Log, transition to `Candidate Answered`, and append exactly one Status History row.
- An allowed outcome that does not change status may append one Call Log only; its values and meaning are not approved yet.
- Reject a call action whose status/outcome combination is invalid; do not create a log and then fail the transition in a separate request.
- Do not let a caller supply or impersonate `Contacted By`/History Actor. Capture the initiating user server-side.
- A repeated identical request returns the original result. Reusing its key with a different action/payload returns a conflict, not a success-shaped response.
- Exact non-answer outcomes, whether call time can be backdated, phone/email channel requirements, and whether calls are allowed after the first state remain product decisions.

## 10. Server-Enforced Transition Contract

**Proposed Dataverse Custom API:** unique name `os_sr_cact`, display name **Apply Candidate Action**, unbound Action with required `CandidateId` input. Its synchronous main-operation plug-in owns the transition validation and transaction boundary.

Inputs:

| Input | Type | Rule |
|---|---|---|
| `CandidateId` | Guid | Required; target Candidate. |
| `ActionType` | String | Required allowlisted action; never accept arbitrary target state. |
| `ExpectedStatus` | Integer | Required for transitions; must match current status. |
| `IdempotencyKey` | String | Required opaque URL-safe value. |
| `Reason` | String | Conditional; owner-approved rules determine when required. |
| `CorrelationId` | String | Conditional, nonsecret. |
| `CallOutcome` | String | Required for `RecordCall`; exact approved taxonomy unresolved. |
| `ContactedAt` | DateTime | Required for `RecordCall`; represents business event, not server creation time. |
| `Notes` | String | Optional and minimized. |
| `RescheduleEvidenceId` | String | Required for reschedule; must resolve to approved persisted cancellation/reconciliation evidence from a future feature. |

Outputs are deterministic: `ResultCode` (`Applied` or `DuplicateReplay`), previous/current status, and created Call Log/History IDs when applicable. Failures return explicit stable validation/conflict/authorization codes; no success-shaped fallback.

The plug-in must retrieve authoritative state, validate action/status/evidence, derive actor/time, enforce optimistic concurrency, and write Candidate + applicable children in one Dataverse transaction. Verify the Custom API transaction setting and synchronous plug-in execution behavior before implementation. If atomicity cannot be guaranteed, stop; do not split state and history writes across calls or Flow steps. External calendar/email calls are excluded.

## 11. Concurrency / Idempotency Design

- Use Candidate `versionnumber`/row version and conditional update (`IfRowVersionMatches` semantics); verify Candidate optimistic concurrency is enabled. Status equality alone does not prevent concurrent lost updates.
- Use unique alternate keys `(Candidate, Action Idempotency Key)` on Call Log and Status History; no email alternate key.
- Generate a new opaque key for each logical action; retrying the same request reuses it. Never generate a new key merely to get past an uncertain result.
- For an existing key, compare action/payload to distinguish exact replay from key reuse with changed intent. Exact replay returns the persisted outcome; a changed payload is rejected.
- The call's log, Candidate status update, and History row share one synchronous Dataverse transaction. A duplicate-key or stale-row conflict must roll the transaction back with no partial records.
- Candidate status update uses `ExpectedStatus` and row-version check. Distinguish stale/concurrent conflict from invalid workflow transition.
- Do not add a custom version field unless actual platform concurrency cannot meet the need. No automatic retry after an uncertain metadata or business operation.

## 12. Security Model

No roles or access were changed or assigned in Phase 3A. Proposed future effective privileges:

| Table | BSO (subject to approved role) | Admin |
|---|---|---|
| Candidate | Create/Read/Write for non-status fields; no Delete. Status field changes only via Custom API. Assign/Share only if an approved ownership model requires it. | No Admin role assumed; define separately and grant minimum needed. |
| Call Log | Read; no direct Create/Update/Delete. API-controlled append only. | Read only unless an approved correction/retention procedure says otherwise. |
| Status History | Read; no direct Create/Update/Delete. Trusted operation only. | Read only; no routine edit/delete. |

The Custom API must enforce an explicit Execute privilege and authorize the initiating BSO. Any operation identity/privilege arrangement must be least-privileged, auditable, and preserve the initiating actor; no System Administrator shortcut, fixed Flow-owner identity, or silent impersonation is assumed. Exact service execution/security design and field profiles require security-owner review. TA receives no Candidate access by default.

## 13. Privacy / Audit Model

- Candidate Name, Email, Phone, CV URL, Candidate Number, and Call Notes can reveal personal information. Candidate Number and key columns cannot be field-secured; protect them with table/row access.
- Review column security for name, email, phone, and CV URL; a CV URL is sensitive even if no document is stored in Dataverse.
- Minimize free-text notes. Never put full Candidate rows, CV URLs, tokens, secrets, or provider payloads in logs, error text, tests, prompts, or provisioning evidence.
- Proposed table audit scope: Candidate status/owner/selected lookup changes; Call Log and History business changes. Do not audit CV/contact contents until IT/Compliance approves the exact column matrix and retention impact.
- Dataverse auditing supplements `os_sr_csh`; it does not replace it. Existing documentation reports environment auditing disabled and configured retention of 30 days as technical state, not approved policy. No settings were read or changed in Phase 3A.
- Use synthetic fixtures only. No candidate data/CV or tenant-specific connector URL in tests.

## 14. Naming Contract

Names are proposals and use full final names once; Power Apps inputs that prepend `os_` must receive only the `sr_<stem>` remainder.

| Component | Proposed technical name |
|---|---|
| Candidate table | `os_sr_cand` |
| Call Log table | `os_sr_call` |
| Candidate Status History table | `os_sr_csh` |
| Candidate Number / Call Reference / Transition Reference primary names | `os_sr_cand_cnum` / `os_sr_call_ref` / `os_sr_csh_ref` |
| Global status Choice | `os_sr_candstat` |
| Candidate action Custom API | `os_sr_cact` |
| Candidate → Call Log / History relationships | `os_sr_cand_call` / `os_sr_cand_csh` |
| Candidate Number alternate key | `os_sr_cand_ak_cnum` |
| Call / History idempotency keys | `os_sr_call_ak_cand_action` / `os_sr_csh_ak_cand_action` |
| Candidate action plug-in step | `os_sr_cact_stp` |

Field names appear in the proposal manifest. Existing abbreviations (`cand`, `call`, `csh`, `cnum`, `stat`, `actkey`, `corid`, `ctat`, `ctby`, `actr`, `prevstat`, `newstat`, `rsn`, `ref`, `stp`) follow [Data Model](DATA_MODEL.md). Add `cact` = Candidate Action to the private abbreviation dictionary as a proposal before approving component names. Do not double-prefix and do not use names as a security boundary.

## 15. Keys / Integrity

- Candidate key: `os_sr_cand_ak_cnum` on `os_sr_cand_cnum`, conditional on the still-open Candidate Number format/source and key-safe character policy.
- Call idempotency key: `os_sr_call_ak_cand_action` on `os_sr_call_cand` + `os_sr_call_actkey`.
- Status-history idempotency key: `os_sr_csh_ak_cand_action` on `os_sr_csh_cand` + `os_sr_csh_actkey`.
- Candidate email is not globally unique and is not an alternate key.
- Require nonblank key values, stable opaque tokens, maximum allowed field/index sizes, and valid Dataverse alternate-key characters. Verify index activation before relying on a key.
- Require exactly one History row for every accepted transition, and no History row for a rejected or unchanged-state request. Initial Candidate creation at the default is not a transition.
- Relationship integrity: required child-to-Candidate references; restrict hard deletes and preserve inactive parents/children; validate same Candidate for any future multi-lookup operation.
- Correlation IDs are for tracing, not uniqueness. The action idempotency key plus Candidate alternate key is the uniqueness mechanism; add a separate correlation key only if a confirmed business requirement later needs it.

## 16. Provisioning Sequence

No sequence below is authorized in this phase. After all blocking decisions and approvals are resolved, the proposed bounded sequence is:

1. Confirm the exact target environment and active identity under the required guarded workflow; do not log in or switch environments.
2. Verify solution `os_sr_bso_rs_support`, Publisher `os_bso_rs_support`, prefix `os`, option-value range, and exact existing reference lookup targets.
3. Resolve/verify the `os_sr_lgcar` target dependency before creating `os_sr_cand_cand_lgcar`; do not fabricate an external reference table.
4. Create/verify global Choice `os_sr_candstat` with the approved stable values.
5. Create Candidate table and primary name; add non-lookup columns.
6. Create Call Log table and non-lookup columns.
7. Create Candidate Status History table and non-lookup columns.
8. Create lookups/relationships only after target table metadata is confirmed; delete behavior must be Restrict/no cascade.
9. Wait for metadata propagation; create alternate keys only after columns exist, then verify key activation.
10. Verify exact Solution membership and complete metadata by fresh GET-only reads after each authorized write.
11. Implement Custom API/plug-in in a separate bounded phase after security and atomicity review; do not combine schema creation with business-operation code deployment.
12. Publish/reconcile only if required by the actual change and separately authorized. Never use Publish All without explicit authorization.

Separate Candidate/Call/History schema writes from API/plugin implementation for rollback and reconciliation boundaries.

## 17. Metadata Payload Plan

The reviewable, synthetic-only canonical proposal is [PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json). It defines the three tables, status Choice values, lookups/relationships, proposed keys, transition matrix, Custom API contract, and unresolved decisions. It is **not** a Dataverse Web API payload, solution export, generated PAC artifact, or authorization to provision.

Local manifest SHA-256: **37da1392b2cfbd4a2886aa07886b00831775cc73c5f7bd65333ad70ceb334c0d**. This fingerprint identifies the exact JSON proposal file bytes only; it is not a request-body fingerprint. Any future implementation must generate and approve deterministic, operation-specific metadata payloads after the open decisions are closed, then re-check exact hashes immediately before dispatch.

## 18. Provisioning Safety Gates

- Exact target/environment guard plus PAC/Az/WhoAmI and process-scoped expected-user agreement where the guarded project workflow requires them.
- No interactive login, environment switch, token/cache inspection, or tenant connection in this design phase.
- Separate owner approval for each bounded metadata/API/plugin operation; Phase 3A itself authorizes zero writes.
- Exact solution/publisher/prefix, live schema, and dependency preflight; stop on unexpected live state.
- Bounded requests, zero automatic retries for uncertain writes, and GET-only reconciliation after each write before any next write.
- No blind retry; reconcile existing metadata first after any uncertain result.
- No Publish All; never alter the published `srapp` composition/navigation in this scope.
- Synthetic data only; no business rows; no roles/access/audit/DLP changes.

## 19. Offline Test Plan

The new local assertion harness checks the proposal only; it does not claim runtime business-operation tests passed. Future implementation tests must include:

1. Exact three-table scope, `os_sr_` names, primary names, types, requiredness, and system-owned columns.
2. Choice labels, stable distinct integer values, default value, and absence of deprecated TA approval stages.
3. Relationship target, requiredness, restrict-delete/no-cascade policy, and missing LEGO Career dependency detection.
4. Candidate Number, Call Log, and Status History alternate-key definitions and key-safe synthetic values.
5. Every allowed state transition, each negative/skipped/terminal transition, unknown action, and no-op.
6. Expected-status and stale row-version rejection.
7. Concurrent duplicate submissions, same key/same payload replay, and same key/different payload rejection.
8. Exactly one history row per valid transition; zero on rejection; atomic rollback when a child create fails.
9. Call Log + Candidate Answered + History atomic behavior and non-transition call behavior after approved outcomes exist.
10. Reschedule rejection without approved cancellation/reconciliation evidence; no calendar call in this slice.
11. Effective BSO/Admin/TA positive and negative privileges; no direct status write or manual History create/update/delete.
12. Actor derived from initiating identity, no fixed Flow owner impersonation, server UTC transition time, and no PII in logs/fixtures.
13. Exact metadata plan fingerprint and zero network/auth/PAC calls in all offline design tests.

No runtime Custom API, plugin, Dataverse concurrency, or authorization test can pass until an implementation exists in an approved test environment. None is claimed here.

Validation completed: the Phase 3A design harness passed **28** synthetic assertions; the existing reference provisioning/recovery, readiness, and app-composition suites passed **550**, **11**, and **329** synthetic assertions respectively; `git diff --check` passed. These are local checks only.

## 20. Scope Exclusions

Out of Phase 3A: Outlook scheduling; room availability; Teams; interview event create/cancel; Email Center/Dispatch; Visitor Registration; LEGO synchronization; dashboards/KPI; AI Builder; migration; Candidate production data; full end-user role rollout; all changes to the published Phase 2D app/navigation.

The Candidate schema may reference LEGO Career and CV URL because current booking rules require them; this does not implement the sync, validate live postings, or authorize scheduling.

## 21. Open Product Decisions

1. Candidate Number source, generator/manual entry, format, allowed characters, confidentiality, and primary-name suitability.
2. Exact Call Outcome values; which outcomes are retained; which values advance status; call channel/phone requirements; and whether calls can be logged in later statuses.
3. Candidate create-time requiredness for Position, Candidate Source, Email, Phone, and TA.
4. Candidate owner/BSO assignment: creator vs assigned BSO, approved team ownership, transfer/share behavior, and child ownership after transfer.
5. Reschedule evidence source and durable reference; when cancellation/reconciliation counts as sufficient; reason requirement/content policy.
6. Contact/CV field-security profiles, table/column audit matrix, retention and authorized readers. Existing technical audit settings are not policy approval.
7. `os_sr_lgcar` is not among the Phase 2D verified four reference tables. Confirm its separate design/provisioning and ensure it exists before creating the Candidate lookup.
8. Confirm the Custom API execution/privilege arrangement preserves the initiating actor while allowing only least-privilege server writes.
9. Confirm the publisher option-value allocation still permits the proposed Choice integers.

Items 1–3 and 7 materially affect provisioning. Items 4–6 and 8 materially affect security/schema or operation implementation and require owner/security/IT review. No answer is inferred.

## 22. Request / Write Counts

Phase 3A tenant operations:

| Operation | Count |
|---|---:|
| Dataverse GET / metadata reads | 0 |
| Dataverse metadata writes | 0 |
| Candidate / business-data reads or writes | 0 |
| Custom API / plug-in deployment | 0 |
| PublishXml / PublishAllXml | 0 / 0 |
| App/component/Site Map changes | 0 |
| Role/user/team/access changes | 0 |
| Audit/DLP/environment changes | 0 |
| Retries | 0 |

Local PowerShell regression/design tests are not tenant requests.

## 23. Files Changed

Phase 3A changes:

- New [Phase 3A design report](PHASE_3A_CANDIDATE_CORE_DESIGN.md).
- New [synthetic metadata proposal manifest](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json).
- New [offline design assertion test](../tests/Phase3ACandidateCoreDesign.Tests.ps1).
- Updated [test instructions](../tests/README.md), [project context](PROJECT_CONTEXT.md), [current state](CURRENT_STATE.md), [implementation plan](IMPLEMENTATION_PLAN.md), [product decisions](PRODUCT_DECISIONS.md), [data model](DATA_MODEL.md), [schema specification](DATAVERSE_SCHEMA_SPECIFICATION.md), [architecture](ARCHITECTURE.md), and [security model](SECURITY_MODEL.md).

Final worktree: nine modified tracked files and three new in-scope files. No solution source, environment configuration, business data, or published app component is in scope.

## 24. Final Classification

**`BLOCKED_PRODUCT_DECISION`**

The workflow labels and broad relationship/state-machine shape are deterministic enough for review, but unresolved product/security decisions materially affect Candidate identity, call operation validation, owner access, and the Candidate-to-LEGO Career relationship. The criteria for `READY_FOR_CANDIDATE_CORE_PROVISIONING` are therefore not met. No tenant write occurred.

## 25. Exact Recommended Next Task

Obtain written owner/security/IT decisions for items 1–9 in Section 21, with specific resolution of Candidate Number, Call Outcome values, create-time requiredness, BSO ownership, and LEGO Career dependency. Then update the proposal and regenerate its fingerprints/tests. Do **not** provision until the updated report classifies `READY_FOR_CANDIDATE_CORE_PROVISIONING` and a separate bounded write authorization is supplied.

## 26. AI HANDOVER

- Phase 2D remains `PHASE_2D_COMPLETE`; the published reference app/navigation was not touched.
- Candidate, Call Log, and Candidate Status History remain design proposals; none was provisioned.
- Use [the metadata plan](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json) as a proposal snapshot only, not as a request or generated solution artifact.
- The workflow uses the six canonical statuses, defaulting to Need Call Candidate. No legacy TA approval state is allowed.
- Proposed `os_sr_cact` must validate state server-side, compare expected status/version, enforce idempotency, and atomically persist Candidate status, applicable Call Log, and exactly one Status History row.
- Reschedule remains gated on verified cancellation/reconciliation evidence. No calendar cancellation or booking is implemented.
- Candidate Number, Call Outcomes, contact requiredness, owner semantics, audit/security, and LEGO Career target remain open.
- Final classification: `BLOCKED_PRODUCT_DECISION`; all tenant request/write counts are zero.
- Next action: resolve Section 21 decisions, revise and retest the proposal, then seek separate provisioning authorization.
