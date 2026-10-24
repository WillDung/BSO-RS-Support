# Phase 3B.2 — Candidate Core Storage Provisioning Report

**Date:** 24 October 2026
**Final classification:** `STOPPED_AFTER_REJECTED_TABLE_CREATE_NO_RETRY`
**Provisioning execution:** one Call Outcome Choice POST succeeded and reconciled; one Call Log table-create POST returned HTTP 400; no retry
**Final guarded reconciliation:** Candidate exact; Call Outcome Choice present; Call Log and Candidate Status History absent

## 1. Executive Summary

The owner authorized technical normalization and bounded Phase 3B.2 provisioning. The two deterministic `systemuser` relationship names were added to the manifest. A guarded Choice creation POST succeeded; GET reconciliation confirmed the approved labels and Dataverse-allocated values. The current manifest was then updated to freeze those values. A later guarded child-table attempt passed its pre-write checks but its first `EntityDefinitions` POST for Call Log returned HTTP 400. The runner stopped without retrying. A separate guarded read-only reconciliation confirmed Candidate remains exact, the Choice remains present, and both child tables remain absent. Candidate Status History creation was not attempted.

The rejected request's response body was suppressed, so the exact server-side validation error is unknown. No further metadata write may be made under the consumed/stopped authorization. The report does not infer that either child table exists.

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

`b7d0abb9335fd30925911059ef9744a1a519c84338354549768879083cc30ca4`

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

`b7d0abb9335fd30925911059ef9744a1a519c84338354549768879083cc30ca4`

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
| Phase 3B.2 child runner suite | PASS — 12 synthetic assertions |
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

This continuation updates the report, [Current State](CURRENT_STATE.md), [Project Context](PROJECT_CONTEXT.md), [Data Model](DATA_MODEL.md), manifest, design fingerprint, fixed-scope runner guard, and focused synthetic tests. The Call Outcome Choice is the sole successful live metadata change; the Call Log create request was rejected. No other live environment component was changed.

## 27. Final Classification

**`STOPPED_AFTER_REJECTED_TABLE_CREATE_NO_RETRY`**. The Choice was created and reconciled, and the guarded Call Log table-create request was rejected with HTTP 400. The runner stopped without retry; fresh GET reconciliation confirmed Call Log and Candidate Status History remain absent and Candidate remains exact. The exact HTTP 400 validation cause is unknown. The authorization status is recorded as stopped in the manifest and the runner fails closed before target checks or network requests if invoked again under this disposition.

## 28. Exact Recommended Next Task

Under a new explicit bounded authorization, diagnose the rejected Call Log payload using safe local inspection and read-only live reconciliation first. Reconcile the exact manifest and live absence, confirm target/identity/Solution/Publisher guards, then submit only the newly authorized corrected operation with zero retries and immediate readback. Do not retry the rejected payload, recreate the existing Choice, or weaken/repurpose the Candidate-only runner. Organization auditing is disabled; no Candidate business data may be created.

## 29. AI HANDOVER

- Current manifest SHA-256: `b7d0abb9335fd30925911059ef9744a1a519c84338354549768879083cc30ca4`.
- PAC/Az/Dataverse identity and process-scoped expected-user guards passed during guarded provisioning; exact Candidate, Solution, and Publisher checks passed.
- `os_sr_callout` exists in the approved Solution and is frozen as Answered `100010000`, No Answer `100010001`, Call Back Requested `100010002`.
- Call Log table-create POST returned HTTP 400; no retry. Final GET-only reconciliation confirmed both Call Log and Candidate Status History absent; Candidate remains exact.
- Relationship names are frozen locally: `os_sr_usr_call_ctby` and `os_sr_usr_csh_actr`, plus Candidate links `os_sr_cand_call` and `os_sr_cand_csh`. No child relationships or keys were written.
- Organization audit was freshly read as disabled; no organization setting was changed.
- Guarded POST count: 2 (one successful Choice create, one rejected Call Log table create); GET aggregate unavailable in retained output; zero retries.
- Manifest authorization status is `STOPPED_AFTER_REJECTED_TABLE_CREATE_NO_RETRY`; the runner blocks future requests/writes under this stopped authorization.
- No Candidate changes, business data, app changes, publication, roles, or access changes occurred.
- No commit or push occurred.
