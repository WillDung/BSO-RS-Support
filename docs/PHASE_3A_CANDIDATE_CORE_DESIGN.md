# Phase 3A — Candidate Core Domain Design & Provisioning Readiness Report

**As of:** 24 October 2026
**Current Candidate-only schema status:** `CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED`
**Current Phase 3B.2 status:** `STOPPED_AFTER_REMAINING_METADATA_MISMATCH_NO_FURTHER_WRITES`
**Full Candidate Core classification:** `BLOCKED_STATUS_HISTORY_CHOICE_BINDING_MISMATCH_AND_EXTERNAL_AUDIT_API_PRIVILEGE_PREREQUISITES`
**Phase:** Owner-approved design; Candidate, Call Outcome Choice, Call Log, Candidate Status History, four approved relationships, and two Active child keys are present and GET-reconciled. However, both Candidate Status History status fields are bound to `os_sr_callout` instead of approved Choice `os_sr_candstat`. No further metadata write is authorized; Custom API/plugin, publication, app/access changes, and business records remain outside the completed slice.

**Phase 3A.1 follow-up:** The first closure attempt received no owner-authored choices; its historical result remains in the [Phase 3A.1 report](PHASE_3A1_CANDIDATE_CORE_DECISION_CLOSURE.md). On 23 October 2026, the owner explicitly approved all eight decision areas. This revision applies those decisions and records remaining external gates in the [Phase 3A.2 decision application and readiness report](PHASE_3A2_CANDIDATE_CORE_DECISION_APPLICATION.md).

## 1. Executive Summary

The owner-approved design has a deterministic shape for Candidate, Call Log, Candidate Status History, the status and call-outcome Choices, and the server-enforced operation contract. Approved requirements include server-generated nonpersonal Candidate Numbers; Answered / No Answer / Call Back Requested outcomes; required Candidate Name and Email with optional Phone; Dataverse Owner as the responsible BSO; a mandatory reschedule reason; table auditing for all three tables; caller-generated GUID CorrelationId idempotency; and deferral of the LEGO Career lookup to the later scheduling/booking boundary. The Candidate Status Choice and Candidate table-only schema (including two Active alternate keys and three approved lookups) are now provisioned and GET-reconciled under the separate bounded authorization recorded in the [Candidate-only provisioning report](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md). No Candidate business rows were created.

Further Candidate Core work is blocked by the Phase 3B.2 Choice-binding mismatch and external gates, not unresolved owner product choices. Organization-level auditing is disabled, with retention/access/capacity governance still open; the least-privilege Custom API execution privilege model has not been approved or tested. No Candidate data may be created while organization auditing remains disabled. Candidate Status Choice allocation/binding, Candidate AutoNumber metadata, Candidate table audit flag, keys, lookup targets, and Solution inclusion are verified. The Call Outcome Choice is also provisioned and reconciled with Answered `100010000`, No Answer `100010001`, and Call Back Requested `100010002`. Call Log and Candidate Status History tables, their audit flags, all four approved child relationships, and both Active alternate keys are present. Fresh read-only reconciliation found that `os_sr_csh_prevstat` and `os_sr_csh_newstat` both bind to `os_sr_callout` instead of `os_sr_candstat`; no further write is authorized. The synthetic proposal snapshot and current execution state are in [the metadata plan](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json).

The proposal uses global Choices `os_sr_candstat` and `os_sr_callout`, and one synchronous server operation, `os_sr_cact`, with a main-operation plug-in. Direct status editing is blocked. Candidate state, an applicable Call Log, and exactly one Status History row must commit atomically. Non-answer calls create only a Call Log. Reschedule requires a reason and captures actor, server timestamp, CorrelationId, previous/new status, and reason; actual calendar/event cancellation evidence and execution remain deferred to the scheduling phase. Booking, interview-result capture, email, and integrations remain out of this slice.

## 2. Repository / Phase Baseline

- Repository: `BSO-RS-Support`; branch `main`.
- Phase 3A.2 starting HEAD: `3ead7282c09911d4275f931cb905247533a9df64` on `main`; `origin/main` matched at start.
- Phase 3A.2 starting worktree: clean; the owner-approved decision revision began from that baseline.
- Phase 2D reference-app milestone: `PHASE_2D_COMPLETE`. Published `srapp` remains the reference-administration app only; this work does not alter it.
- Current verified app pages remain TA Directory, Positions, Candidate Sources, and Locations; the published `srapp` was not changed. Candidate is present in the Solution; Call Log and Candidate Status History remain unprovisioned.
- The exact approved reference tables (`os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, `os_sr_loc`) exist. No Candidate-to-LEGO-Career lookup is included in the Phase 3A core proposal.
- Project table prefix contract is `os_sr_*`; solution name is `os_sr_bso_rs_support`.
- No ATSugg source schema or live candidate data was inspected.
The Phase 3A.2 revision is local and uncommitted. No commit, push, restore, stash, branch switch, pull, or rebase was performed.

## 3. Candidate Table Design

**Candidate table:** `os_sr_cand` / Candidate; `UserOwned`; table audit metadata enabled. The table and listed columns have been GET-reconciled. Candidate Number runtime generation remains untested because no Candidate row was created.

| Candidate column | Type / limit | Classification | Requiredness / rule |
|---|---|---|---|
| `os_sr_cand_cnum` — Candidate Number | Dataverse AutoNumber, `CAND-{SEQNUM:8}`; String/Text, maximum length 100; primary name | Required | Server-generated, immutable after creation, unique, nonpersonal; protected by a unique alternate key. The length is owner-approved. Runtime generation remains unverified until a later authorized synthetic-row test. |
| `os_sr_cand_nm` — Candidate Name | Text, 200 | Required | Personal information; required at Candidate creation. No column-level security in this initial slice; protect by table/row access and auditing. |
| `os_sr_cand_eml` — Candidate Email | Email text, 254 | Required | Required at Candidate creation. No column-level security in this initial slice; not unique and not an alternate key. |
| `os_sr_cand_phn` — Candidate Phone | Phone text, 50 | Optional | Optional at Candidate creation. No column-level security in this initial slice. |
| `os_sr_cand_corid` — Creation Correlation ID | GUID text, 36 | Required for operation-created records | Caller-generated GUID; unique alternate key prevents duplicate Candidate creation for one logical operation. |
| `os_sr_cand_pos` — Position | Lookup to `os_sr_pos` | Recommended | Included in Candidate core; optional at creation; do not infer title uniqueness. |
| `os_sr_cand_csrc` — Candidate Source | Lookup to `os_sr_csrc` | Recommended | Optional at creation in the current proposal; retain historical source meaning. |
| `os_sr_cand_ta` — Assigned TA | Lookup to `os_sr_ta` | Conditional | Required before booking; TA remains an interviewer/directory contact, not an approval role. |
| `os_sr_cand_cvurl` — Candidate CV URL | URL text, 2,000 | Conditional, sensitive | Booking prerequisite under current rules; host/access/retention remain later booking-boundary decisions. |
| `os_sr_cand_stat` — Candidate Workflow Status | Global Choice `os_sr_candstat` | Required | Default `Need Call Candidate`; no direct interactive editing. |
| `ownerid` | Dataverse system lookup | System | The record Owner is the responsible BSO. Candidate creation assigns the authenticated initiating BSO as Owner; no duplicate Assigned BSO lookup is added. |
| `createdon`, `createdby`, `modifiedon`, `modifiedby` | Dataverse system columns | System | Do not duplicate as custom columns. |
| `versionnumber` | Dataverse row version | System | Use for optimistic concurrency if enabled and verified; do not add a custom workflow version without a demonstrated need. |

Do not put candidate name, email, phone, CV URL, salary, interview result, or free-form notes in the primary name or technical identifiers. Email is not a globally unique identity key. The accepted Candidate Number format proposal contains no personal information; Dataverse generation and an active unique key enforce its intended uniqueness.

## 4. Candidate Status Design

**Representation:** global Dataverse Choice `os_sr_candstat`, created once and GET-reconciled against the approved labels and frozen allocated values. It is intended to be shared by Candidate and the future Status History table.

| Allocated integer | Label | Default |
|---|---|---|
| 100010000 | Need Call Candidate | Yes |
| 100010001 | Candidate Answered | No |
| 100010002 | Waiting Manual Scheduling | No |
| 100010003 | Round 1 Scheduled | No |
| 100010004 | Offer Extended | No |
| 100010005 | Candidate Failed | No |

The approved Candidate-only run sent null option values; Dataverse allocated the values shown, which were GET-reconciled with all six labels and frozen in the manifest. The Publisher option-value prefix was verified as `10001`. Never infer values from labels or recreate the Choice for preferred integers. Application code should use the frozen values, not compare localized labels. `statecode/statuscode` remain separate platform Active/Inactive fields.

Block direct UI, Web API, and Flow status changes. Only the approved Dataverse business operation may transition state. Initial creation at the default status is not a transition and does not create a fabricated history row.

## 4A. Call Outcome Design

**Owner-approved initial outcomes:** global Choice `os_sr_callout`.

| Allocated integer | Outcome | Candidate effect from Need Call Candidate |
|---|---|---|
| GET-reconciled | Answered | Atomically create Call Log, transition to Candidate Answered, and create one Status History row. |
| GET-reconciled | No Answer | Create Call Log only; Candidate remains Need Call Candidate; no Status History row. |
| GET-reconciled | Call Back Requested | Create Call Log only; Candidate remains Need Call Candidate; no Status History row. |

The three labels are owner-approved. Let Dataverse allocate values during the later Call Outcome Choice provisioning, then GET-reconcile and freeze them before Custom API/plugin implementation. No other initial outcome is allowed. Invalid outcome/status combinations fail closed.

## 5. Call Log Design

**Proposed table:** `os_sr_call` / Call Log; `UserOwned`; append-only through the approved action.

| Proposed column | Type / limit | Requiredness / rule |
|---|---|---|
| `os_sr_call_ref` — Call Reference | Autonumber Text, `CALL-{SEQNUM:8}` | System-generated nonpersonal primary name; sequence gaps are acceptable. |
| `os_sr_call_cand` — Candidate | Lookup to `os_sr_cand` | Required; parent deletion restricted. |
| `os_sr_call_out` — Call Outcome | Global Choice `os_sr_callout` | Required; only Answered, No Answer, and Call Back Requested are allowed in the initial slice. |
| `os_sr_call_ctat` — Contacted At | Date/Time, User Local | Required business-event time; distinct from record creation time. |
| `os_sr_call_ctby` — Contacted By | Lookup to `systemuser` | Required; resolve from authenticated initiating identity, not a client-supplied user or fixed Flow owner. |
| `os_sr_call_nts` — Notes | Multiline Text, 4,000 | Optional; minimize and restrict any personal/sensitive detail. |
| `os_sr_call_corid` — Correlation ID | GUID text, 36 | Required for operation-created rows; caller-generated per logical operation and used as the idempotency key. |

Normal BSO application behavior: Read only; no direct Create/Update/Delete. A validated server action appends a row. Whether an administrator may correct/delete under a separately audited retention process is not decided here. Candidate hard-delete must be restricted while child records exist; deactivation must not delete call evidence. A unique alternate key on Candidate + CorrelationId prevents duplicate operation submissions.

`Answered` from `Need Call Candidate` creates the Call Log, transitions Candidate to `Candidate Answered`, and creates exactly one Status History row atomically. `No Answer` and `Call Back Requested` create a Call Log only and leave Candidate status unchanged.

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
| `os_sr_csh_rsn` — Reason | Multiline Text, 1,000 | Required for reschedule. |
| `os_sr_csh_corid` — Correlation ID | GUID text, 36 | Required for every operation-created transition row; caller-generated per logical operation. |
| `os_sr_csh_cact` — Candidate Action | Text, 50 | Required, operation-controlled allowlisted action name. |

Each accepted reschedule history row records the authenticated actor, server-generated UTC timestamp, CorrelationId, previous/new status, and mandatory reason in the same transaction. Normal application access is Read only. Direct user Create/Update/Delete must be denied or blocked by a server-enforced write guard; only the trusted operation creates rows. `Delete=Restrict` and no cascade delete/assign/share/reparent. Ownership is set by the server operation; a lookup does not itself grant row access.

The purpose-built history is the business transition record, not a substitute for Dataverse auditing. Audit settings and retention remain subject to IT/Compliance approval.

## 7. Relationship Model

| Parent → child | Relationship / lookup | Requiredness | Delete / cascade |
|---|---|---|---|
| Candidate → Call Log | `os_sr_cand_call` / `os_sr_call_cand` | Required | Restrict delete; no cascade on assign/share/reparent. |
| Candidate → Candidate Status History | `os_sr_cand_csh` / `os_sr_csh_cand` | Required | Restrict delete; preserve history. |
| Position → Candidate | `os_sr_pos_cand` / `os_sr_cand_pos` | Candidate lookup proposed optional | Restrict; deactivate reference, do not delete history. |
| Candidate Source → Candidate | `os_sr_csrc_cand` / `os_sr_cand_csrc` | Candidate lookup proposed optional | Restrict; preserve historical source. |
| TA Directory → Candidate | `os_sr_ta_cand` / `os_sr_cand_ta` | Conditional, required before booking | Restrict; TA is not an app approver. |

Candidate ownership is the security boundary; child records do not inherit access by lookup. Candidate Owner is the responsible BSO; creation uses the authenticated initiating BSO. The operation must set child ownership deliberately. No relationship cascade should delete call or status-history evidence when a Candidate or reference row is deactivated. LEGO Career is excluded from Candidate core; the later booking boundary owns linked-career validation.

## 8. Transition Matrix

| Current status | Action / qualifying result | Next status | Allowed? | Guard |
|---|---|---|---|---|
| Need Call Candidate | `RecordCall` with Answered | Candidate Answered | Yes | Same transaction appends Call Log and one History row. |
| Need Call Candidate | `RecordCall` with No Answer | Need Call Candidate | Yes, no transition | Create Call Log only; do not create History or change status. |
| Need Call Candidate | `RecordCall` with Call Back Requested | Need Call Candidate | Yes, no transition | Create Call Log only; do not create History or change status. |
| Candidate Answered | `ProceedToScheduling` | Waiting Manual Scheduling | Yes | Candidate core does not require a LEGO Career lookup; the later booking boundary validates CV URL and linked career. |
| Waiting Manual Scheduling | `MarkRound1Scheduled` | Round 1 Scheduled | Yes | Only after a future scheduler reports a verified successful booking. |
| Round 1 Scheduled | `RecordPass` | Offer Extended | Yes | Requires future authorized Pass result evidence. |
| Round 1 Scheduled | `RecordFail` | Candidate Failed | Yes | Requires future authorized Fail result evidence. |
| Round 1 Scheduled | `RequestReschedule` | Need Call Candidate | Deferred to scheduling phase | Requires mandatory reason; the later scheduling phase must implement and evidence the cancellation attempt before this operation is enabled. |
| Any status | Same status / no-op “transition” | Same status | No | No transition or duplicate history row. |
| Need Call Candidate | Skip directly to Waiting Manual Scheduling or Round 1 Scheduled | Any later status | No | Reject skipped states. |
| Candidate Answered | Return directly to Need Call Candidate | Need Call Candidate | No | Reschedule path is only from Round 1 Scheduled. |
| Waiting Manual Scheduling | Pass / Fail / Offer Extended / Candidate Failed | Terminal status | No | No result transition before a Round 1 Scheduled state and valid result evidence. |
| Offer Extended | Arbitrary rollback | Any earlier status | No | Terminal in this workflow. |
| Candidate Failed | Arbitrary rollback | Any earlier status | No | Terminal in this workflow. |
| Any status | Legacy Draft Created / BSO Reviewing / Sent to TA / TA Approval | Any | No | Deprecated stages are prohibited. |
| Any status | Unknown action, stale status, missing evidence, unauthorized caller | Any | No | Fail closed with no partial writes. |

The six statuses, three initial outcomes, and mandatory reschedule reason are owner-approved. Calendar/event cancellation evidence and execution are deliberately deferred; this design does not claim the reschedule action is currently executable.

## 9. Call Action Contract

Proposed single entry point: `os_sr_cact` (“Apply Candidate Action”). Every state-changing operation requires a caller-generated GUID `CorrelationId`, reused only when retrying the same logical operation. For `RecordCall`, it validates the authenticated BSO, Candidate ID, current expected status, CorrelationId, contacted timestamp, and one of the three approved outcomes.

- `Answered` from `Need Call Candidate` atomically appends one Call Log, transitions to `Candidate Answered`, and appends exactly one Status History row.
- `No Answer` and `Call Back Requested` append one Call Log only and leave status unchanged.
- Reject a call action whose status/outcome combination is invalid; do not create a log and then fail the transition in a separate request.
- Do not let a caller supply or impersonate `Contacted By`/History Actor. Capture the initiating user server-side.
- A repeated identical request returns the original result. Reusing its CorrelationId with a different action/payload returns a conflict, not a success-shaped response.
- Call time can be backdated only under the validated input rule; do not invent additional outcomes. No Answer and Call Back Requested are valid only from `Need Call Candidate` in this initial slice.

## 10. Server-Enforced Transition Contract

**Proposed Dataverse Custom API:** unique name `os_sr_cact`, display name **Apply Candidate Action**, unbound Action implemented by a synchronous main-operation plug-in. `CandidateId` is required except for `CreateCandidate`; every state-changing operation requires `CorrelationId` as a GUID.

Inputs:

| Input | Type | Rule |
|---|---|---|
| `CandidateId` | Guid | Required except for `CreateCandidate`; target Candidate. |
| `ActionType` | String | Required allowlisted action, including Candidate create/update and workflow actions; never accept arbitrary target state. |
| `ExpectedStatus` | Integer | Required for transitions; must match current status. |
| `CorrelationId` | Guid | Required, caller-generated, one per logical state-changing operation; reuse only for its retry. |
| `CandidateName` | String | Required for `CreateCandidate`. |
| `CandidateEmail` | String | Required for `CreateCandidate`. |
| `CandidatePhone` | String | Optional for `CreateCandidate`. |
| `PositionId` / `CandidateSourceId` | Guid | Optional Candidate lookups; Position is included in core. |
| `Reason` | String | Required for `RequestReschedule`. |
| `CallOutcome` | Choice integer | Required for `RecordCall`; only Answered, No Answer, or Call Back Requested. |
| `ContactedAt` | DateTime | Required for `RecordCall`; represents business event, not server creation time. |
| `Notes` | String | Optional and minimized. |

Outputs are deterministic: `ResultCode` (`Applied` or `DuplicateReplay`), previous/current status, and created Call Log/History IDs when applicable. Failures return explicit stable validation/conflict/authorization codes; no success-shaped fallback.

Candidate creation assigns `ownerid` from the authenticated initiating BSO and lets Dataverse generate Candidate Number; clients cannot provide or later update the number. The plug-in must retrieve authoritative state, validate action/status, derive actor/time, enforce optimistic concurrency, and write Candidate + applicable children in one Dataverse transaction. Verify the Custom API transaction setting and synchronous plug-in execution behavior before implementation. If atomicity cannot be guaranteed, stop; do not split state and history writes across calls or Flow steps. External calendar/email calls are excluded. `RequestReschedule` remains disabled until the later scheduling phase supplies the required cancellation-attempt boundary.

## 11. Concurrency / Idempotency Design

- Use Candidate `versionnumber`/row version and conditional update (`IfRowVersionMatches` semantics); verify Candidate optimistic concurrency is enabled. Status equality alone does not prevent concurrent lost updates.
- Use unique alternate keys on Candidate creation CorrelationId, `(Candidate, CorrelationId)` on Call Log, and `(Candidate, CorrelationId)` on Status History; no email alternate key.
- The caller generates a GUID CorrelationId for each logical state-changing operation; retrying the same operation reuses it. Never generate a new ID merely to get past an uncertain result.
- For a persisted correlation key, compare action/payload to distinguish exact replay from key reuse with changed intent. Exact replay returns the persisted outcome; a changed payload is rejected.
- `UpdateCandidate` uses replacement values: an identical replay is a no-op and cannot append a Call Log, History row, or status transition. Its CorrelationId is still mandatory.
- The call's log, Candidate status update, and History row share one synchronous Dataverse transaction. A duplicate-key or stale-row conflict must roll the transaction back with no partial records.
- Candidate status update uses `ExpectedStatus` and row-version check. Distinguish stale/concurrent conflict from invalid workflow transition.
- Do not add a custom version field unless actual platform concurrency cannot meet the need. No automatic retry after an uncertain metadata or business operation.

## 12. Security Model

No roles or access were changed or assigned in Phase 3A. Proposed future effective privileges:

| Table | BSO (subject to approved role) | Admin |
|---|---|---|
| Candidate | Create/Read/Write only through the approved Custom API, including Name, Email, Phone, and status; no Delete. Owner is the responsible BSO. | No Admin role assumed; define separately and grant minimum needed. |
| Call Log | Read; no direct Create/Update/Delete. API-controlled append only. | Read only unless an approved correction/retention procedure says otherwise. |
| Status History | Read; no direct Create/Update/Delete. Trusted operation only. | Read only; no routine edit/delete. |

The Custom API must enforce an explicit Execute privilege and authorize the initiating BSO. Any operation identity/privilege arrangement must be least-privileged, auditable, and preserve the initiating actor; no System Administrator shortcut, fixed Flow-owner identity, or silent impersonation is assumed. The exact privilege/effective-access model remains an external security approval and test prerequisite. TA receives no Candidate access by default.

## 13. Privacy / Audit Model

- Candidate Name, Email, Phone, CV URL, Candidate Number, and Call Notes can reveal personal information. Candidate Number and key columns cannot be field-secured; protect them with table/row access.
- Do not apply column-level security to Candidate Name, Email, or Phone in this initial slice, as explicitly approved. Protect them through least-privilege table/row access and auditing. A CV URL remains sensitive and requires its later booking-boundary access/retention design.
- Minimize free-text notes. Never put full Candidate rows, CV URLs, tokens, secrets, or provider payloads in logs, error text, tests, prompts, or provisioning evidence.
- Owner-approved requirement: enable Dataverse table auditing for Candidate, Call Log, and Candidate Status History. Do not apply column-level security to Candidate Name, Email, or Phone in this initial slice. Dataverse auditing supplements `os_sr_csh`; it does not replace it.
- The last documented environment assessment reports organization-level auditing disabled and configured retention of 30 days, which is not an approved policy. IT/Compliance must resolve organization-level activation, retention, audit access, legal-hold/DSR, and capacity governance before audit can be relied on. No settings were read or changed in this design task.
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
| Creation / Call / History correlation keys | `os_sr_cand_ak_corid` / `os_sr_call_ak_cand_action` / `os_sr_csh_ak_cand_action` |
| Call outcome Choice | `os_sr_callout` |
| Candidate action plug-in step | `os_sr_cact_stp` |

Field names appear in the proposal manifest. Existing abbreviations (`cand`, `call`, `csh`, `cnum`, `stat`, `actkey`, `corid`, `ctat`, `ctby`, `actr`, `prevstat`, `newstat`, `rsn`, `ref`, `stp`) follow [Data Model](DATA_MODEL.md). Add `cact` = Candidate Action to the private abbreviation dictionary as a proposal before approving component names. Do not double-prefix and do not use names as a security boundary.

## 15. Keys / Integrity

- Candidate key: `os_sr_cand_ak_cnum` on Dataverse-generated `os_sr_cand_cnum`; `os_sr_cand_ak_corid` on creation CorrelationId.
- Call idempotency key: `os_sr_call_ak_cand_action` on `os_sr_call_cand` + `os_sr_call_corid`.
- Status-history idempotency key: `os_sr_csh_ak_cand_action` on `os_sr_csh_cand` + `os_sr_csh_corid`.
- Candidate email is not globally unique and is not an alternate key.
- Require nonblank canonical GUID correlation values, maximum allowed field/index sizes, and valid Dataverse alternate-key characters. Verify index activation before relying on a key.
- Require exactly one History row for every accepted transition, and no History row for a rejected or unchanged-state request. Initial Candidate creation at the default is not a transition.
- Relationship integrity: required child-to-Candidate references; restrict hard deletes and preserve inactive parents/children; validate same Candidate for any future multi-lookup operation.
- CorrelationId is both the trace identifier and per-operation idempotency token. Distinct alternate keys scope it to Candidate creation, Call Log, and Status History effects; check payload equivalence before returning a replay.

## 16. Provisioning Sequence

No sequence below is authorized in this phase. After all blocking decisions and approvals are resolved, the proposed bounded sequence is:

1. Confirm the exact target environment and active identity under the required guarded workflow; do not log in or switch environments.
2. Verify solution `os_sr_bso_rs_support`, Publisher `os_bso_rs_support`, prefix `os`, both Choice value allocations, and exact existing Position, Candidate Source, and TA lookup targets.
3. Resolve organization-level auditing, retention, audit access, and capacity prerequisites under approved IT/Compliance governance; stop if table audit cannot be made effective.
4. Confirm supported AutoNumber creation for `os_sr_cand_cnum` and the approved generation/immutability enforcement.
5. Create/verify global Choices `os_sr_candstat` and `os_sr_callout` with their approved labels and verified/frozen values.
6. Create Candidate table with AutoNumber primary name and non-lookup columns, including Creation CorrelationId; create its table audit flag.
7. Create Call Log and Candidate Status History with their GUID CorrelationId fields and table audit flags.
8. Create lookups only to confirmed existing Candidate, Position, Candidate Source, TA Directory, Call Log, and History targets; LEGO Career is excluded from this slice.
9. Wait for metadata propagation; create alternate keys only after columns exist, then verify key activation.
10. Verify exact Solution membership and complete metadata by fresh GET-only reads after each separately authorized write.
11. Implement Custom API/plug-in in a separate bounded phase after least-privilege execution review and atomicity verification; do not combine schema creation with business-operation code deployment.
12. Publish/reconcile only if required by the actual change and separately authorized. Never use Publish All without explicit authorization.

Separate Candidate/Call/History schema writes from API/plugin implementation for rollback and reconciliation boundaries.

## 17. Metadata Payload Plan

The synthetic canonical proposal and current verified Candidate-only state are in [PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json). It defines the three-table target, status and call-outcome Choices, lookups/relationships, keys, transition matrix, Custom API contract, owner-decision record, and external prerequisites. It is **not** a Dataverse Web API payload, solution export, or generated PAC artifact.

Local manifest SHA-256: **59180b226555ef44b4c41da73b902e8faa001fa87cb4dc10e1eaf661541bf72b**. This fingerprint identifies the exact JSON file bytes only; it is not a request-body fingerprint. The Phase 3B.2 execution record and local payload contract were updated to record the latest GET-only `PARTIAL_METADATA_STATE` stop and enforce the already-approved child primary-name metadata; no Candidate or child-table product/schema semantics were changed.

## 18. Provisioning Safety Gates

- Exact target/environment guard plus PAC/Az/WhoAmI and process-scoped expected-user agreement where the guarded project workflow requires them.
- No interactive login, environment switch, token/cache inspection, or tenant connection in this design phase.
- Separate owner approval for each bounded metadata/API/plugin operation; the Candidate-only authorization has been consumed.
- Exact solution/publisher/prefix, live schema, and dependency preflight; stop on unexpected live state.
- Bounded requests, zero automatic retries for uncertain writes, and GET-only reconciliation after each write before any next write.
- No blind retry; reconcile existing metadata first after any uncertain result.
- No Publish All; never alter the published `srapp` composition/navigation in this scope.
- Synthetic data only; no business rows; no roles/access/environment audit/DLP changes in this design task.

## 19. Offline Test Plan

The new local assertion harness checks the proposal only; it does not claim runtime business-operation tests passed. Future implementation tests must include:

1. Exact three-table scope, `os_sr_` names, generated Candidate Number, required Name/Email, optional Phone, owner assignment, and system-owned columns.
2. Status and Call Outcome Choice labels, stable distinct integer values, default value, and absence of deprecated TA approval stages.
3. Position, Candidate Source, and TA relationship targets; restrict-delete/no-cascade policy; no Candidate-to-LEGO-Career relationship.
4. Candidate Number and CorrelationId alternate-key definitions and key-safe synthetic values.
5. Every allowed state transition, each negative/skipped/terminal transition, unknown action, and no-op.
6. Expected-status and stale row-version rejection.
7. Concurrent duplicate submissions, same CorrelationId/same payload replay, and same CorrelationId/different payload rejection.
8. Exactly one history row per valid transition; zero on rejection; atomic rollback when a child create fails.
9. Answered Call Log + Candidate Answered + History atomic behavior; No Answer/Call Back Requested create Call Log only.
10. Mandatory reschedule reason and complete History evidence; action remains unavailable until later cancellation-attempt support; no calendar call in this slice.
11. Effective BSO/Admin/TA positive and negative privileges; no direct status write or manual Call/History create/update/delete.
12. Actor derived from initiating identity, no fixed Flow owner impersonation, server UTC transition time, and no PII in logs/fixtures.
13. Exact metadata plan fingerprint and zero network/auth/PAC calls in all offline design tests.

No runtime Custom API, plugin, Dataverse concurrency, or authorization test can pass until an implementation exists in an approved test environment. None is claimed here.

Validation is rerun after the owner-approved design revision; counts and exact outcomes are recorded in the Phase 3A.2 report. These are local checks only.

## 20. Scope Exclusions

Out of Phase 3A: Outlook scheduling; room availability; Teams; interview event create/cancel; Email Center/Dispatch; Visitor Registration; LEGO synchronization; dashboards/KPI; AI Builder; migration; Candidate production data; full end-user role rollout; all changes to the published Phase 2D app/navigation.

Candidate core does not include a LEGO Career lookup, career synchronization, CV validation, or booking. The later scheduling/booking boundary must enforce the approved linked-career and CV prerequisites before booking.

## 21. Owner Decisions and Remaining External Gates

The owner decisions for Candidate Number, call outcome taxonomy, Candidate Name/Email/Phone requiredness, Dataverse Owner as responsible BSO, mandatory reschedule reason/history, table audit and contact field-security policy, GUID CorrelationId idempotency, and LEGO Career deferral are recorded as approved in the Phase 3A.2 report. No owner product decision from Phase 3A.1 remains open.

External prerequisites remain:

1. Enablement and governance for organization-level Dataverse auditing. The last documented environment review found auditing disabled; retention, authorized audit readers, legal-hold/DSR, and capacity ownership remain to be settled by IT/Compliance.
2. Least-privilege Custom API Execute privilege/effective-access design and validation; preserve the authenticated initiating BSO without System Administrator or fixed Flow-owner impersonation.
3. Candidate-only provisioning remains exact. Phase 3B.2 created/reconciled the Call Outcome Choice and both child tables, then dispatched the four approved relationships and two alternate keys. The latest GET-only reconciliation confirms these components but finds both Status History status columns bound to the wrong global Choice (`os_sr_callout`, expected `os_sr_candstat`). The seven-write remaining authorization is consumed; corrective work requires new explicit authorization. See the [Phase 3B.2 report](PHASE_3B2_CANDIDATE_CHILD_TABLES_REPORT.md).
4. Before any further metadata operation, verify the exact target, publisher, Solution, and dependencies in a fresh guarded preflight.
5. Implement cancellation-attempt evidence before enabling the reschedule action in the later scheduling phase. This is an explicitly deferred implementation dependency, not an unresolved Candidate Core product choice.

These items do not change the accepted Candidate Core product requirements. The Phase 3B.2 status-field Choice binding mismatch blocks acceptance of child-table schema; audit governance blocks Candidate data creation and reliance on audit history; API privilege design blocks Custom API/plugin implementation. Candidate-only schema provisioning is complete.

## 22. Request / Write Counts

The original Phase 3A design/readiness assessment made no tenant requests. A later separately authorized Candidate-only metadata run is recorded in the [provisioning report](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md). Its final read-only reconciliation sent 31 GET and 0 POST; the bounded run's total authorized writes were seven, with zero retries and zero business-data writes.

Original Phase 3A design-task tenant operations:

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

Phase 3A.2 owner-decision revision updates the design and manifest, records decisions in the new [Phase 3A.2 report](PHASE_3A2_CANDIDATE_CORE_DECISION_APPLICATION.md), and synchronizes [Current State](CURRENT_STATE.md), [Product Decisions](PRODUCT_DECISIONS.md), [Data Model](DATA_MODEL.md), [Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md), [Business Workflows](BUSINESS_WORKFLOWS.md), [Security Model](SECURITY_MODEL.md), [Architecture](ARCHITECTURE.md), [Project Context](PROJECT_CONTEXT.md), [Implementation Plan](IMPLEMENTATION_PLAN.md), [Phase 3A.1 historical closure](PHASE_3A1_CANDIDATE_CORE_DECISION_CLOSURE.md), and the offline assertion harness plus [test instructions](../tests/README.md).

No solution source, environment configuration, business data, or published app component is in scope.

## 24. Final Classification

**`BLOCKED_STATUS_HISTORY_CHOICE_BINDING_MISMATCH_AND_EXTERNAL_AUDIT_API_PRIVILEGE_PREREQUISITES` for further Candidate Core implementation.**

All owner product decisions are recorded. Candidate-only metadata is exact. Phase 3B.2's seven remaining metadata writes completed without retry, but final reconciliation found two Status History attributes bound to the wrong Choice; the authorization is consumed and no corrective write was attempted. Organization auditing is disabled, so no Candidate business data may be created; the least-privilege Custom API execution privilege model remains unapproved/untested. No Candidate data, API/plugin, app, access, or publication change occurred.

## 25. Exact Recommended Next Task

First obtain new bounded authorization to plan a non-destructive correction for `os_sr_csh_prevstat` and `os_sr_csh_newstat`, currently bound to `os_sr_callout` but required to bind to `os_sr_candstat`; start with fresh read-only metadata reconciliation and supported-correction analysis. Do not retry table/relationship/key creation or modify Candidate. Separately resolve organization-audit governance before Candidate data creation and approve/test least-privilege Custom API execution before API/plugin implementation.

## 26. AI HANDOVER

- Phase 2D remains `PHASE_2D_COMPLETE`; the published reference app/navigation was not touched.
- Candidate Status Choice and Candidate table schema (two Active keys, three approved lookups) are provisioned and GET-reconciled. Call Outcome Choice, Call Log, Candidate Status History, four relationships, and two Active keys are present. The two Status History status fields have an incorrect Choice binding, so Phase 3B.2 remains blocked; its remaining-write authorization is consumed.
- Use [the metadata plan](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json) as the synthetic design/current-state manifest, not as a request or generated solution artifact.
- The workflow uses the six canonical statuses, defaulting to Need Call Candidate. No legacy TA approval state is allowed.
- Proposed `os_sr_cact` must require a caller-generated GUID CorrelationId for every state-changing operation, compare expected status/version, and atomically persist Candidate status, applicable Call Log, and exactly one Status History row.
- Answered logs and transitions atomically; No Answer and Call Back Requested log only. Reschedule requires a reason and full history evidence but stays disabled until the later cancellation-attempt boundary is implemented.
- Candidate Number, call outcomes, contact requiredness, Owner-as-BSO, auditing, contact field-security, and LEGO Career deferral are owner-approved decisions.
- Organization auditing is disabled; no Candidate records were created and none may be created until audit governance is resolved.
- Candidate-only provisioning used seven authorized writes, zero retries, and a final GET-only reconciliation (31 GET, 0 POST). Phase 3B.2's corrected Call Log create plus seven remaining-scope writes were dispatched once; the latest child-scope reconciliation returned 17 GET and 0 POST. No Candidate data or other prohibited writes occurred.
- Next action: obtain a new bounded authorization to correct the two History Choice bindings after supported non-destructive repair analysis; do not repeat any of the seven writes. Organization auditing and API privilege design remain separate gates.
