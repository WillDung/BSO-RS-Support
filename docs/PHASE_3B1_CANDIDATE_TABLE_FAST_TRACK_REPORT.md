# Phase 3B.1 — Candidate Table Fast-Track Provisioning Report

**Disposition date:** 24 October 2026  
**Final classification:** `CANDIDATE_ALREADY_EXISTS`  
**Current-request tenant operations:** 0 requests, 0 writes  
**Scope:** Candidate table only; no additional provisioning was attempted.

## 1. Executive Summary

The Candidate table and its approved schema were already created and successfully reconciled in the separately authorized 23 October 2026 Candidate-only run. That authorization is recorded as consumed. The current attachment specifies a prerequisite manifest SHA-256 of `8e035cc64451817efb8342fec245df2aa5e943eb3bd81fe3d5393ee9185d2e08`; the current local manifest is `7cfe13bb7450946c17e3659e02a4b78aecfd93f50c272561b1e88c6084d566d1`. Because the baseline differs and the most recent live evidence already confirms Candidate exists, the request stopped without authentication or a new live preflight. No write was dispatched.

This is a report of the request disposition and the last verified state, not a claim that live metadata was refreshed on 24 October.

## 2. Git / Baseline

| Item | Before this report |
|---|---|
| Branch | `main` |
| HEAD | `652157e62ea0af1c1cf0b67b80a88bd5586cda90` |
| `origin/main` | `652157e62ea0af1c1cf0b67b80a88bd5586cda90` |
| Worktree | Clean |
| Current manifest SHA-256 | `7cfe13bb7450946c17e3659e02a4b78aecfd93f50c272561b1e88c6084d566d1` |
| Attachment-required manifest SHA-256 | `8e035cc64451817efb8342fec245df2aa5e943eb3bd81fe3d5393ee9185d2e08` |
| Fingerprint comparison | Mismatch; no environment operation was started |

The report and Current State update below are local documentation changes only. No reset, restore, stash, pull, rebase, branch switch, commit, or push was performed.

## 3. Actual Authentication Path

Source inspection of [`Provision-BsoRsCandidateTable.ps1`](../scripts/Provision-BsoRsCandidateTable.ps1) shows that the Dataverse bearer token is obtained through `Az.Accounts\Get-AzAccessToken` after checking the existing Az context against the PAC identity. The runner validates token audience, tenant, delegated scope, and expiry; it then compares PAC identity with Dataverse `WhoAmI` and pins the expected user in the process.

**Source-path classification:** `AZURE_IDENTITY_CREDENTIAL_PATH`.

This is a classification of the runner implementation, not evidence that the current request acquired a token. No authentication command or token acquisition was executed for this disposition.

## 4. Target / Identity Guards

The prior successful run reported that its guarded process verified the approved VN LMV IT target, PAC/Az identity agreement, Dataverse `WhoAmI`, process-scoped expected-user pin, Solution `os_sr_bso_rs_support`, Publisher `os_bso_rs_support`, and prefix `os`. Those checks are documented in the [Candidate-only provisioning evidence](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md).

They were not re-run for this request. Environment URLs, organization/environment identifiers, user IDs, tokens, and other sensitive identity values are intentionally omitted.

## 5. Pre-Write Live Schema

The last successful live reconciliation found `os_sr_cand` present. The current request performed no fresh schema GETs because the required local manifest fingerprint did not match and the documented Candidate creation authorization had already been consumed. The `CANDIDATE_ALREADY_EXISTS` classification therefore relies on the 23 October verified state and must not be read as a new 24 October live observation.

The prior reconciliation also recorded Call Log and Candidate Status History as not created. No current-request check was made for drift in those components.

## 6. Publisher / Choice Allocation

Prior GET reconciliation verified the Candidate Status global Choice `os_sr_candstat` and its exact frozen mapping:

| Allocated value | Label |
|---:|---|
| 100010000 | Need Call Candidate |
| 100010001 | Candidate Answered |
| 100010002 | Waiting Manual Scheduling |
| 100010003 | Round 1 Scheduled |
| 100010004 | Offer Extended |
| 100010005 | Candidate Failed |

This request did not re-read the Publisher, option-value allocation, or Choice.

## 7. Audit Environment State

The last verified run found Candidate table audit metadata enabled and organization-level auditing disabled. IT/Compliance governance for organization audit activation, retention, audit access, and capacity remains an external prerequisite. No Candidate records may be created until that gate is resolved. No audit setting was changed or queried in this request.

## 8. Candidate Metadata Plan

The currently recorded Candidate definition is limited to the approved Candidate table, Candidate Status Choice, two alternate keys, and lookups to the existing Position, Candidate Source, and TA Directory tables. It excludes Call Log, Candidate Status History, LEGO Career, Custom API, plug-in, roles, app components, Site Map, forms/views authoring, and business records. The last verified metadata details are listed in the [Candidate-only provisioning evidence](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md).

## 9. Planned Write Count / Fingerprints

The attachment's baseline fingerprint did not match the current manifest, so no executable write plan or request payload was generated for this attempt. Planned write count for this request: **0**. The runner's local default plan-only execution independently reported **0 Dataverse requests and 0 writes** using the current manifest; this did not dispatch anything.

Current manifest SHA-256: `7cfe13bb7450946c17e3659e02a4b78aecfd93f50c272561b1e88c6084d566d1`. Current Candidate-only projection SHA-256: `7168980f2d13d8e406a25854fef3dafad118673e1c5661fb9461e52f41b4f7d8`.

## 10. Candidate Table Create

Not attempted in this request. The last verified run already created `os_sr_cand`; this request did not issue an `EntityDefinitions` POST.

## 11. Candidate Scalar Columns

Not created or changed in this request. The last verified Candidate table definition included its approved fields. No Candidate data was created.

## 12. Candidate Reference Lookups

Not created or changed in this request. The last verified Candidate relationships were:

- `os_sr_pos_cand` to Position (`os_sr_pos`)
- `os_sr_csrc_cand` to Candidate Source (`os_sr_csrc`)
- `os_sr_ta_cand` to TA Directory (`os_sr_ta`)

## 13. Candidate Status Choice

No Choice write or GET was made in this request. The six-value Choice mapping above remains the last verified mapping.

## 14. Candidate Number AutoNumber

No metadata write or runtime test was made in this request. Last verified metadata: String MaxLength 100, AutoNumber format `CAND-{SEQNUM:8}`. Classification from the prior run: `AUTONUMBER_METADATA_VERIFIED`; runtime generation remains untested because no Candidate row was created.

## 15. Candidate Number Key

No key operation was made in this request. The last verified Candidate Number unique alternate key and Correlation ID alternate key were both Active.

## 16. Choice Value Freeze

The values listed in Section 6 are frozen in the current manifest and documented design following the prior GET reconciliation. The attachment's earlier fingerprint is stale relative to that completed state. No values were changed or reallocated.

## 17. Audit Result

Last verified audit outcome: `CANDIDATE_AUDIT_SCHEMA_READY_ENVIRONMENT_ACTIVATION_PENDING`. No organization setting or table audit metadata was changed.

## 18. API Privilege Deferral

`API_PRIVILEGE_VALIDATION_DEFERRED_UNTIL_TABLE_EXISTS` remains the recorded status. The API and plug-in were not created. Future least-privilege Execute privilege design and effective-access validation require their own approved scope.

## 19. Final Candidate Schema Reconciliation

No new reconciliation was executed on 24 October. The most recent documented GET-only reconciliation reported the Candidate definition and Solution root/subcomponent membership exact, with **31 GET and 0 POST** for that final reconciliation. This previous evidence is not represented as a same-day verification.

## 20. Scope Exclusion Proof

This request executed no tenant operations. The previous provisioning report records no Candidate data, Call Log, Candidate Status History, Call Outcome Choice, Custom API, plug-in, app/navigation, publication, role/access, or organization-setting writes. No claim of a new absence check is made here.

## 21. Request / Write Counts

| Operation | This request | Prior completed Candidate-only run |
|---|---:|---:|
| GET | 0 | Final GET-only reconciliation: 31 (other run reads are not totaled here) |
| `EntityDefinitions` POST | 0 | 1 Candidate table |
| Attribute POST | 0 | 0 separate attribute POSTs; attributes were part of table create |
| Relationship POST | 0 | 3 |
| Choice metadata writes | 0 | 1 |
| Key writes | 0 | 2 |
| `PublishXml` | 0 | 0 |
| `PublishAllXml` | 0 | 0 |
| App writes | 0 | 0 |
| Business-data writes | 0 | 0 |
| Retries | 0 | 0 |
| **Total metadata writes** | **0** | **7** |

## 22. No-Retry Proof

No request was sent; retries were therefore **0**. The prior bounded run also records zero automatic retries. No timeout or uncertain current-request outcome occurred.

## 23. Regression Results

All validation was local and synthetic:

| Check | Result |
|---|---|
| Phase 3A Candidate metadata/design assertions | PASS — 43 |
| Reference provisioning regression assertions | PASS — 550 |
| Readiness assertions | PASS — 11 |
| Model-driven app composition assertions | PASS — 329 |
| PowerShell parser | PASS — provisioning runner plus four test scripts, 0 diagnostics |
| Runner default plan-only mode | PASS — 0 Dataverse requests, 0 writes |
| Manifest SHA-256 / runner / design fingerprint consistency | PASS for current `7cfe13…` state; does not match the attachment's prior `8e035c…` prerequisite |
| `git diff --check` | PASS |
| Privacy scan of added diff lines | PASS — no email addresses, absolute URLs, bearer tokens, secret assignments, or GUID identifiers |
| Relative Markdown links | PASS — report links and the new Current State cross-link resolve |

These checks do not refresh live state or prove current tenant availability.

## 24. Files Changed

For this disposition, only this report and [Current State](CURRENT_STATE.md) are intended to change. Existing provisioning scripts, manifest schema, Choice values, and live components were not modified. The prior successful run and its original seven metadata writes are recorded separately in the [Candidate-only provisioning evidence](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md).

## 25. Final Classification

**`CANDIDATE_ALREADY_EXISTS`**, based on the last verified 23 October live reconciliation. The request stopped before authentication because the supplied manifest fingerprint did not match the current manifest and the Candidate creation authorization had already been consumed. No fresh 24 October live state is claimed.

## 26. Exact Recommended Next Task

Do not repeat Candidate table provisioning. If a new schema or business-operation slice is desired, first resolve organization-level audit governance and least-privilege Custom API execution design, then prepare a new bounded scope and authorization. Any live action must use a newly confirmed target and fresh guarded preflight; Candidate record creation remains prohibited until the audit prerequisite is resolved.

## 27. AI HANDOVER

- Candidate-only metadata was previously provisioned and reconciled; the original authorization is consumed.
- Current manifest fingerprint is `7cfe13bb7450946c17e3659e02a4b78aecfd93f50c272561b1e88c6084d566d1`; the attachment's `8e035c…` fingerprint describes an earlier proposal state.
- The prior live read found organization auditing disabled. No Candidate data may be created.
- No tenant calls, writes, publication, access changes, commit, or push occurred for this report disposition.
- The full Solution export was not retained; no solution source snapshot is present under `solutions/`.
