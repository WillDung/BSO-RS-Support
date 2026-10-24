# Phase 3B.2 — Candidate Core Storage Provisioning Report

**Date:** 24 October 2026
**Current classification:** `PARTIAL_METADATA_STATE`
**Latest provisioning execution:** the prior corrected Call Log create and seven remaining metadata POSTs were each dispatched once; zero retries
**Latest read-only reconciliation:** Candidate exact; both child tables, four relationships, and two Active keys present; both Candidate Status History status columns bind to the wrong global Choice. The latest resume made 17 GET and 0 POST.

> The original HTTP 400 attempt is retained below as historical evidence. The latest bounded continuation and current handover are recorded in Section 30 and supersede earlier statements that the child tables were absent.

## 1. Executive Summary

The owner-authorized initial Phase 3B.2 attempt created and reconciled the Call Outcome Choice, then its Call Log create returned HTTP 400. That original failure and its zero-retry disposition are historical. The owner later approved the corrected primary-name metadata and one corrected Call Log create dispatch, followed by remaining child metadata if Call Log reconciled exactly. The corrected Call Log create returned successfully, its immediate GET returned HTTP 404, and subsequent GET-only reconciliation found it present and exact. A guarded resume then dispatched exactly seven remaining-scope metadata writes. Final read-only reconciliation found both child tables, their four approved relationships, and both Active keys, but exposed a Choice-binding mismatch on the two Candidate Status History status attributes. No retry or corrective write was sent.

The original HTTP 400 body remains unavailable, so its exact cause is unknown. The later approved normalization set both child String/AutoNumber primary-name MaxLength values to 100 and FormatName to Text. The remaining-scope runner incorrectly supplied the Call Outcome Choice metadata for every GlobalChoice column, so the two Status History status fields were bound to `os_sr_callout` instead of `os_sr_candstat`. This mismatch is directly verified by fresh read-only metadata. The seven-write authorization is consumed; no additional tenant write is authorized by it. No Candidate or business records were created.

## 2. Git / Manifest Baseline

| Item | At resumed run start |
|---|---|
| Branch | `main` |
| HEAD | `ab5502aba7188c1477f31a956e5f02335759041e` |
| Worktree | Changes were made during this continuation; no commit or push |
| Manifest path | `docs/PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json` |

No reset, restore, stash, pull, rebase, branch switch, commit, or push was performed for this run.

## 3. Current Manifest SHA

The final local manifest SHA-256 after freezing the live Choice mapping and recording the stopped authorization is:

`9bf9be601451f307ca523eac2a8a109e1dd32be4ba11b71d499f66688390d435`

Manifest identity: solution `os_sr_bso_rs_support`, Publisher prefix `os`, project namespace `sr_`. It contains the Candidate Core tables, seven unique relationships, and frozen `os_sr_callout` labels/values. The child continuation status is now `STOPPED_AFTER_REJECTED_TABLE_CREATE_NO_RETRY`; both provisioning-runner manifest pins match this SHA. A future attempt requires new bounded authorization and a new safe diagnosis of the rejected payload.

## 4. Authentication Path

The resumed guarded process acquired a Dataverse bearer token through `Az.Accounts\Get-AzAccessToken`, after PAC identity checks. It validated the actual token context against PAC, including Dataverse audience/scope/tenant/expiry, and confirmed identity agreement with Dataverse `WhoAmI`. The runner's credential path is therefore `AZURE_IDENTITY_CREDENTIAL_PATH`; the current-request credential was used only for the authorized read-only reconciliation.

The Candidate-only runner was used for fresh reconciliation before the child scope and again after the rejected request. A separate child-table runner handled Choice preflight/provisioning, child preflight, and the one Call Log create request. Its authorization has now been stopped locally; it refuses the stopped disposition before target checks or network calls.

## 5. Target / Identity Guards

The owner reconfirmed the organization URL in the current request. PAC `env who` reported the approved VN LMV IT environment and an Org URL matching the supplied URL exactly. The request did not persist user/environment/organization identifiers in this report.

The guarded runs re-ran PAC identity checks, validated the actual Az token credential context against PAC and its Dataverse audience/scope/tenant/expiry, called `WhoAmI`, and confirmed PAC/WhoAmI identity agreement. The process-scoped expected-user pin was established from the verified request identity. Solution and Publisher linkage/prefix guards passed. No login or environment switch occurred.

## 6. Fresh Candidate Live State

The final guarded read-only reconciliation freshly confirmed Candidate is present and exact; Call Log (`os_sr_call`) and Candidate Status History (`os_sr_csh`) are absent. The `os_sr_callout` Choice exists in the approved Solution and reconciles to the exact frozen manifest labels and values. Organization auditing remains disabled. No business rows were read or written.

## 7. Candidate Reconciliation

Classification for this run: **`CANDIDATE_RECONCILED_EXACT`**.

Fresh reconciliation verified Candidate table identity, UserOwned ownership, primary name, audit metadata, all approved custom attributes/types/requiredness/lengths, Candidate Number AutoNumber format and MaxLength, Status Choice binding and default, both alternate keys (Active), all three approved reference lookups/relationships, and Solution root/subcomponent inclusion. No Candidate create, replacement, destructive, or corrective operation was attempted.

## 8. Candidate Choice Mapping

The fresh reconciliation GET returned the following actual `os_sr_candstat` mapping:

| Value | Label |
|---:|---|
| 100010000 | Need Call Candidate |
| 100010001 | Candidate Answered |
| 100010002 | Waiting Manual Scheduling |
| 100010003 | Round 1 Scheduled |
| 100010004 | Offer Extended |
| 100010005 | Candidate Failed |

Values were read from live option metadata, not inferred from label ordering.

## 9. Organization Audit State

The guarded reconciliation freshly read organization audit state as **disabled**. Candidate table audit metadata is enabled. No organization audit setting was changed.

The current manifest requires table-audit metadata for Candidate, Call Log, and Candidate Status History. Organization audit inactivity alone does not authorize changing the environment setting; no Candidate workflow/business data is authorized in this run.

## 10. Remaining Table Preflight

Fresh pre-write GETs found both child tables absent, the Choice present and exact, and all four required child lookup relationship names available and collision-free. The scoped write plan was limited to the Choice if absent, two child tables, four relationships, and two alternate keys. The Choice already existed after the successful Choice POST, so the later child-table attempt did not recreate it.

## 11. Call Log Payload

The guarded runner constructed one `EntityDefinitions` table-create payload for the approved `UserOwned`, audit-enabled Call Log table. Its primary name is `os_sr_call_ref` (`CALL-{SEQNUM:8}`); it includes the approved Candidate lookup, Call Outcome, Contacted At, Contacted By, operation Correlation ID, optional Notes (maximum 4,000), and alternate key `os_sr_call_ak_cand_action` over Candidate and Correlation ID. Dataverse rejected that POST with HTTP 400. The exact response body was not retained; therefore the specific validation cause is unknown. No retry was sent. Subsequent GET reconciliation confirmed the table remains absent.

The normalized relationships are `os_sr_cand_call` (Candidate → Call Log) and `os_sr_usr_call_ctby` (System User → Call Log, Contacted By). Both were in the allowlisted proposal; neither was written because table creation failed.

## 12. Status History Payload

No Status History table-create payload was dispatched. The manifest describes a `UserOwned`, audit-enabled table with primary name `os_sr_csh_ref` (`HIST-{SEQNUM:8}`), required Candidate, Previous Status, New Status, Actor, Changed At, and Candidate Action; Reason (maximum 1,000) is required for reschedule, and Correlation ID is required for operation-created transitions. The alternate key is `os_sr_csh_ak_cand_action` over Candidate and Correlation ID.

The normalized relationships are `os_sr_cand_csh` (Candidate → Candidate Status History) and `os_sr_usr_csh_actr` (System User → Candidate Status History, Actor). The table and relationships remain unprovisioned.

## 13. Planned Write Counts / Fingerprints

Candidate reconciliation, Choice reconciliation, and the complete fixed-scope preflight passed. The Call Log EntityDefinitions payload had a guarded local hash recorded by the runner, but the rejected request body was not retained in this report. The fingerprint in Section 3 is the final manifest hash, not a request-body fingerprint.

The attempted write scope was limited to `os_sr_callout` (created once), the two child tables, four relationships, and two alternate keys. Candidate create/replacement, Custom API, plug-in, roles, app/Site Map, publishing, and business records remained excluded.

## 13a. Local HTTP 400 Payload Diagnosis

Read-only source inspection found one concrete payload omission: `New-TablePayload` generated the AutoNumber primary-name `StringAttributeMetadata` without `MaxLength`, while neither child table's current manifest `primaryName` defines a length. This can make the metadata payload invalid; however, the server response content was suppressed and is unavailable, so the HTTP 400 cause remains **unconfirmed**. The local runner now fails closed before building a child-table payload unless an explicit valid `primaryName.maxLength` is present, and includes that value in the generated attribute. No value was selected or written to the manifest because the approved design does not specify one. A new bounded authorization and an explicit approved length are prerequisites before any future table-create attempt.

## 14. Call Log Provisioning

One table-create POST was attempted and rejected with HTTP 400. Subsequent GET-only reconciliation confirmed Call Log remains absent. Automatic retries: **0**.

## 15. Call Log Reconciliation

Not attempted after Call Log table creation was rejected. Its fields, Choice linkage, Candidate lookup, relationships, key, audit flag, and Solution membership remain unprovisioned; the final read confirmed the table is absent.

## 16. Status History Provisioning

Not attempted. Table-create writes: **0**.

## 17. Status History Reconciliation

Not performed. Its fields, status Choice bindings, Candidate lookup, relationship, key, audit flag, and Solution membership remain unverified for this run.

## 18. Relationship Reconciliation

The fresh Candidate reconciliation verified the three existing Candidate reference relationships and their inclusion through the Candidate root. The current manifest defines seven relationships total:

- Candidate → Call Log: `os_sr_cand_call`, lookup `os_sr_call_cand`.
- Candidate → Candidate Status History: `os_sr_cand_csh`, lookup `os_sr_csh_cand`.
- Position → Candidate: `os_sr_pos_cand`.
- Candidate Source → Candidate: `os_sr_csrc_cand`.
- TA Directory → Candidate: `os_sr_ta_cand`.

The four proposed child relationships use Delete Restrict and no Assign/Share/Reparent cascade. They were included in preflight but were not written or live-reconciled. Their frozen names are `os_sr_cand_call`, `os_sr_cand_csh`, `os_sr_usr_call_ctby`, and `os_sr_usr_csh_actr`.

## 19. Choice Freeze

The `os_sr_callout` Choice was created once and GET-reconciled in the approved Solution. Its exact values are:

| Value | Label |
|---:|---|
| 100010000 | Answered |
| 100010001 | No Answer |
| 100010002 | Call Back Requested |

These allocated values are frozen in the manifest before Custom API/plugin implementation. The Choice was not recreated after the later Call Log rejection.

## 20. Final Manifest SHA

The live Choice mapping and relationship names were frozen locally, and the failed execution disposition was recorded. Final SHA-256 is:

`9bf9be601451f307ca523eac2a8a109e1dd32be4ba11b71d499f66688390d435`

## 21. Full Candidate Core Storage State

The resulting Phase 3B.2 storage state is partial: Candidate remains exact; Call Outcome Choice exists with the frozen mapping; Call Log and Candidate Status History are absent. No child relationships or keys were created. Organization auditing is disabled; no business data was created.

## 22. Deferred Custom API / Security Scope

No Custom API, plug-in, Execute privilege, role, app, Site Map, form/view, scheduling, Outlook, Teams, email flow, LEGO Career, or Candidate business-record operation was performed.

Status for handover: **`API_PRIVILEGE_READY_FOR_NEXT_PHASE_REVIEW`**. Candidate is now freshly verified to exist, so API privilege design may be reviewed in a later phase. It does not mean that an API privilege was inspected, validated, or approved. No final API security validation was done here.

## 23. Request / Write Counts

| Operation | Count |
|---|---:|
| Guarded provisioning/reconciliation GET requests (aggregate) | Not retained in the available sanitized run summary |
| Metadata POST requests | 2 |
| Successful metadata creates | 1 — Call Outcome Choice |
| Rejected metadata POST | 1 — Call Log EntityDefinitions, HTTP 400 |
| Child table creates | 0 successful |
| Attribute / relationship / key writes | 0 |
| Candidate create / update / destructive writes | 0 |
| Business-data writes | 0 |
| App / Site Map writes | 0 |
| `PublishXml` | 0 |
| `PublishAllXml` | 0 |
| Automatic retries | 0 |
| **All guarded tenant requests** | **GET total unavailable / 2 POST** |

## 24. No-Retry Proof

No automatic retry occurred. The Call Outcome Choice was POSTed once and confirmed by readback. The Call Log table-create POST was rejected once and then reconciled by fresh GET-only reads as absent. No attempt was made to repeat either POST. The rejected request's exact server-side validation message is unknown. The available sanitized handoff summary does not retain a complete aggregate GET counter; no total is inferred.

## 25. Regression Results

| Check | Result |
|---|---|
| Phase 3A design / current manifest suite | PASS — 46 synthetic assertions |
| Phase 3B.2 child runner suite | PASS — 14 synthetic assertions |
| Candidate reconciliation | PASS — fresh guarded reconciliation; exact Candidate schema, Choice mapping, keys, relationships, and Solution inclusion |
| Call Outcome Choice | PASS — created once, GET-reconciled with exact labels/values and Solution membership |
| Child-table create/reconciliation | BLOCKED — Call Log POST returned HTTP 400; both child tables are GET-confirmed absent |
| Child relationships, keys, and child audit metadata | NOT provisioned |
| Reference provisioning suite | PASS — 550 synthetic assertions |
| Readiness suite | PASS — 11 synthetic assertions |
| App composition suite | PASS — 329 synthetic assertions |
| Privacy scan of report and newly added Current State lines | PASS — no email addresses, absolute URLs, bearer tokens, secret assignments, or GUID identifiers |
| Relative Markdown links in this report | PASS |
| PowerShell parser | PASS — provisioning runner and focused test scripts, 0 diagnostics |
| `git diff --check` and untracked-report whitespace | PASS |

Synthetic tests validate local proposal/regression behavior only; they are not a substitute for live Candidate reconciliation or metadata provisioning.

## 26. Files Changed

This continuation updates the report, [Current State](CURRENT_STATE.md), [Project Context](PROJECT_CONTEXT.md), [Data Model](DATA_MODEL.md), manifest, design fingerprint, fixed-scope runner guard, and focused synthetic tests. The Call Outcome Choice is the sole successful live metadata change; the Call Log create request was rejected. A local fail-closed check for the missing child primary-name MaxLength was added; no schema length was chosen. No other live environment component was changed.

## 27. Final Classification

**`STOPPED_AFTER_REJECTED_TABLE_CREATE_NO_RETRY`**. The Choice was created and reconciled, and the guarded Call Log table-create request was rejected with HTTP 400. The runner stopped without retry; fresh GET reconciliation confirmed Call Log and Candidate Status History remain absent and Candidate remains exact. The exact HTTP 400 validation cause is unknown. The authorization status is recorded as stopped in the manifest and the runner fails closed before target checks or network requests if invoked again under this disposition.

## 28. Exact Recommended Next Task

First obtain an explicit approved `MaxLength` for both child AutoNumber primary-name columns and a new bounded authorization. Then perform fresh read-only reconciliation and target/identity/Solution/Publisher guards before preparing a corrected payload. Do not retry the rejected payload, recreate the existing Choice, or weaken/repurpose the Candidate-only runner. Organization auditing is disabled; no Candidate business data may be created.

## 29. AI HANDOVER

- Current manifest SHA-256: `9bf9be601451f307ca523eac2a8a109e1dd32be4ba11b71d499f66688390d435`.
- PAC/Az/Dataverse identity and process-scoped expected-user guards passed during guarded provisioning; exact Candidate, Solution, and Publisher checks passed.
- `os_sr_callout` exists in the approved Solution and is frozen as Answered `100010000`, No Answer `100010001`, Call Back Requested `100010002`.
- Call Log table-create POST returned HTTP 400; no retry. Final GET-only reconciliation confirmed both Call Log and Candidate Status History absent; Candidate remains exact.
- Relationship names are frozen locally: `os_sr_usr_call_ctby` and `os_sr_usr_csh_actr`, plus Candidate links `os_sr_cand_call` and `os_sr_cand_csh`. No child relationships or keys were written.
- Organization audit was freshly read as disabled; no organization setting was changed.
- Guarded POST count: 2 (one successful Choice create, one rejected Call Log table create); GET aggregate unavailable in retained output; zero retries.
- Local diagnosis: table payload omitted primary-name `MaxLength`; likely invalid-payload cause, not confirmed because the HTTP 400 body was suppressed. Both child primary-name lengths remain unspecified; runner now blocks payload construction until set.
- Manifest authorization status is `STOPPED_AFTER_REJECTED_TABLE_CREATE_NO_RETRY`; the runner blocks future requests/writes under this stopped authorization.
- No Candidate changes, business data, app changes, publication, roles, or access changes occurred.
- No commit or push occurred.

## 30. Latest Corrected Continuation and Read-Only Reconciliation

**Date:** 24 October 2026
**Current classification:** `STOPPED_AFTER_REMAINING_METADATA_MISMATCH_NO_FURTHER_WRITES`

### 30.1 Corrected Call Log Create

The one explicitly authorized corrected `EntityDefinitions` POST for `os_sr_call` returned successfully. Its immediate GET returned HTTP 404, so the runner stopped without retry. A later GET-only reconciliation confirmed Call Log exists in the approved Solution with `UserOwned` ownership, auditing enabled, root inclusion of subcomponents, primary name `os_sr_call_ref`, String MaxLength 100, Text format, AutoNumber format `CALL-{SEQNUM:8}`, and the approved pre-relationship custom attributes. Its Call Outcome field is bound to `os_sr_callout`.

### 30.2 Remaining-Scope Dispatch

After the existing Call Log reconciled, a same-process guarded resume dispatched the seven remaining approved metadata writes exactly once:

| Metadata component | POSTs | Result |
|---|---:|---|
| Candidate Status History table | 1 | HTTP success response; later read as present |
| Approved child relationships | 4 | HTTP success responses; later read as present |
| Approved alternate keys | 2 | HTTP success responses; later read as Active |
| **Total remaining-scope writes** | **7** | Authorization consumed; automatic retries 0 |

No Call Log create was repeated. The run made no Candidate, business-data, Custom API/plugin, security/access, app/navigation, or publication writes.

### 30.3 Fresh GET-Only Reconciliation

The subsequent child-scope reconciliation completed with **17 GET, 0 POST**, and zero retries. Candidate reconciled exact. Both child tables are present, UserOwned, audit-enabled, and included as Solution roots with subcomponents. The four approved relationships exist with Delete Restrict and NoCascade Assign/Share/Reparent. Both approved two-column alternate keys are Active:

- `os_sr_call_ak_cand_action`: Candidate + Correlation ID.
- `os_sr_csh_ak_cand_action`: Candidate + Correlation ID.

The Call Outcome Choice remains exact and has one Solution association. Organization-level auditing remains disabled; no business rows were created.

### 30.4 Blocking Metadata Mismatch

The approved manifest requires both `os_sr_csh_prevstat` and `os_sr_csh_newstat` to bind to global Choice `os_sr_candstat`. Fresh read-only `PicklistAttributeMetadata` expansion instead reports both bound to `os_sr_callout`. This is a verified schema mismatch, not a readback uncertainty. The local payload-builder defect was that it reused the Call Outcome Choice metadata for every Choice column rather than resolving each field's manifest `target`. The local builder is corrected to select the metadata by target and the offline tests cover that distinction; this code correction does not repair deployed metadata.

The seven-write remaining-scope authorization is consumed. No attribute update, replacement, recreate, relationship retry, key retry, or other corrective write was attempted. **Do not run the writer again under this consumed authorization.** Any correction requires new bounded owner authorization, fresh target and metadata preflight, and a supported non-destructive correction plan. Do not create Candidate records while organization auditing is disabled.

### 30.5 Current Manifest and Request Accounting

The current manifest SHA-256 is `4ad1f47edaea1ee23add24c8aa5e8566357c3e913bf30ac198397f73b98e7bb1`. The latest reconciliation's 17 GET / 0 POST count is the child runner's count; the separately invoked Candidate reconciler's request count is not included in that counter. During the guarded resume, the child runner reported 35 GET and 7 POST before final validation stopped at the first Choice-binding mismatch. Aggregate cross-runner GET totals are not asserted.

| Boundary | Count |
|---|---:|
| Corrected Call Log table create | 1 POST |
| Remaining-scope metadata writes | 7 POST |
| Automatic retries | 0 |
| Candidate schema writes | 0 |
| Business-data writes | 0 |
| App / Site Map / access / publication writes | 0 |

### 30.6 Current Handover

- Candidate and Call Outcome Choice remain exact and unchanged.
- Call Log, Candidate Status History, all four approved relationships, and both Active keys are present.
- The two Candidate Status History Choice columns have the verified wrong binding: `os_sr_callout` instead of `os_sr_candstat`.
- The corrected Call Log create was dispatched once; the seven remaining writes were each dispatched once. Total automatic retries: 0.
- Current authorization is consumed; no further tenant write is authorized.
- Organization auditing is disabled; no Candidate business data was created.
- The local runner now binds each Choice column using its manifest target and has a fail-closed resume path that cannot be used with the consumed authorization.
- No commit or push occurred.

## 31. Latest Resume — Primary-Name Contract and Pre-Write Stop

The requested fresh reconciliation completed before any write. Candidate reconciled exact and unchanged. The Call Outcome Choice remains exact with the three frozen labels/values. Call Log and Candidate Status History are both present, so the conditional corrected table-create prerequisite (“failed table absent”) was false. The two Status History columns remain bound to `os_sr_callout` rather than `os_sr_candstat`; this is an unexpected partial metadata state. The run stopped as **`PARTIAL_METADATA_STATE`** before POST: child-scope requests were **17 GET / 0 POST**, with automatic retries **0**. No table create, metadata correction, or other write was dispatched.

The owner-approved primary-name normalization is now enforced locally for every new child-table payload: `MaxLength` must be explicitly present and exactly `100`, the storage/type contract must be AutoNumber String, `FormatName` must be `Text`, requiredness must remain the manifest's `SystemGenerated` (emitted as `ApplicationRequired`), and SchemaName, DisplayName, `IsPrimaryName=true`, and the manifest AutoNumber format are preserved. The manifest already contained the approved values; the change records/enforces the technical contract and latest execution only, without changing product/schema semantics.

| Fingerprint | SHA-256 |
|---|---|
| Previous manifest | `4ad1f47edaea1ee23add24c8aa5e8566357c3e913bf30ac198397f73b98e7bb1` |
| Corrected manifest | `59180b226555ef44b4c41da73b902e8faa001fa87cb4dc10e1eaf661541bf72b` |
| Corrected Call Log payload from the earlier authorized correction | `18cc58450bdcf5aa03119dc497db37b7842daf61f0f6ed8f8e0987ec0c40f7be` |

The corrected payload fingerprint is historical pre-dispatch evidence for the previously authorized Call Log correction; it was not dispatched during this latest resume because Call Log already exists. The earlier HTTP 400 remains historical; the authorized corrected create later returned success and was GET-reconciled. This run's dispatch count is zero. Historical Phase 3B.2 write attempts remain one corrected Call Log create plus seven remaining-scope metadata writes; automatic retries remain zero. The remaining-scope authorization is consumed, and this reconciliation does not authorize repairing the live Choice mismatch.
