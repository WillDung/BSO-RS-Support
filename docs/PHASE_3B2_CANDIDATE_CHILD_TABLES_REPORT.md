# Phase 3B.2 — Candidate Core Storage Provisioning Report

**Date:** 24 October 2026
**Final classification:** `PRE_WRITE_GATE_BLOCKED`
**Resumed guarded run:** 31 GET / 0 writes / 0 retries

## 1. Executive Summary

The owner reconfirmed the target and directed resumption under the existing Phase 3B.2 authorization. In the resumed guarded process, PAC, Az credential context, and Dataverse `WhoAmI` agreed; the process-scoped expected-user guard was established; the Solution/Publisher linkage passed; Candidate reconciled exactly against the unchanged current manifest; and both child tables were absent. This run made 31 GETs and 0 POSTs.

Provisioning remains blocked before any write: the current manifest does not provide relationship schema names for the required `systemuser` lookups (Contacted By and Actor), and the existing runner is Candidate-only. The Call Outcome Choice was not inspected by this guarded run. No technical names were invented, no child-table payload was dispatched, and the manifest fingerprint remains unchanged.

## 2. Git / Manifest Baseline

| Item | At resumed run start |
|---|---|
| Branch | `main` |
| HEAD | `ab5502aba7188c1477f31a956e5f02335759041e` |
| Worktree | Clean at resumed run start |
| Manifest path | `docs/PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json` |

No reset, restore, stash, pull, rebase, branch switch, commit, or push was performed for this run.

## 3. Current Manifest SHA

The current manifest was parsed locally and its SHA-256 verified before and after the resumed guarded run:

`7cfe13bb7450946c17e3659e02a4b78aecfd93f50c272561b1e88c6084d566d1`

Manifest identity: solution `os_sr_bso_rs_support`, Publisher prefix `os`, project namespace `sr_`. It contains exactly the three Candidate Core tables `os_sr_cand`, `os_sr_call`, and `os_sr_csh`; five relationships; and the `os_sr_callout` Choice with the owner-approved three labels. No obsolete fingerprint was used to modify or reject the current manifest.

## 4. Authentication Path

The resumed guarded process acquired a Dataverse bearer token through `Az.Accounts\Get-AzAccessToken`, after PAC identity checks. It validated the actual token context against PAC, including Dataverse audience/scope/tenant/expiry, and confirmed identity agreement with Dataverse `WhoAmI`. The runner's credential path is therefore `AZURE_IDENTITY_CREDENTIAL_PATH`; the current-request credential was used only for the authorized read-only reconciliation.

The runner was invoked in `-ReconcileOnly` mode. It remains scoped to Candidate reconciliation and excludes Call Log, Candidate Status History, and Call Outcome Choice provisioning.

## 5. Target / Identity Guards

The owner reconfirmed the organization URL in the current request. PAC `env who` reported the approved VN LMV IT environment and an Org URL matching the supplied URL exactly. The request did not persist user/environment/organization identifiers in this report.

The guarded Candidate reconciliation re-ran PAC identity checks, validated the actual Az token credential context against PAC and its Dataverse audience/scope/tenant/expiry, called `WhoAmI`, and confirmed PAC/WhoAmI identity agreement. The process-scoped expected-user pin was established from the verified request identity. The same read-only run verified the manifest Solution and Publisher linkage and prefix. No login or environment switch occurred.

## 6. Fresh Candidate Live State

Fresh live metadata reads were made in the resumed guarded run. Candidate was present. The two remaining manifest tables were reported absent. The Call Outcome Choice `os_sr_callout` was not read by the Candidate-only reconciliation and remains unknown for this run.

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

Fresh metadata GETs found Call Log (`os_sr_call`) and Candidate Status History (`os_sr_csh`) absent. The Call Outcome Choice was not part of the Candidate-only reconciliation and was not checked. No child table was created or fully schema-reconciled.

## 11. Call Log Payload

No Dataverse payload was constructed or dispatched. The current manifest describes a `UserOwned`, audit-enabled table with primary name `os_sr_call_ref` (`CALL-{SEQNUM:8}`), required Candidate lookup, Call Outcome, Contacted At, Contacted By, and operation Correlation ID, optional Notes (maximum 4,000), plus alternate key `os_sr_call_ak_cand_action` over Candidate and Correlation ID.

The manifest does not define the relationship schema name for lookup `os_sr_call_ctby` → `systemuser`. This is a summary of approved local design, not a live payload.

## 12. Status History Payload

No Dataverse payload was constructed or dispatched. The current manifest describes a `UserOwned`, audit-enabled table with primary name `os_sr_csh_ref` (`HIST-{SEQNUM:8}`), required Candidate, Previous Status, New Status, Actor, Changed At, and Candidate Action; Reason (maximum 1,000) is required for reschedule, and Correlation ID is required for operation-created transitions. The alternate key is `os_sr_csh_ak_cand_action` over Candidate and Correlation ID.

The manifest does not define the relationship schema name for lookup `os_sr_csh_actr` → `systemuser`. This is a summary of approved local design, not a live payload.

## 13. Planned Write Counts / Fingerprints

Candidate reconciliation passed, but the missing `systemuser` lookup relationship names prevented a complete approved payload plan. There is no executable ordered write plan or payload hash. The current manifest SHA in Section 3 is the design fingerprint retained for this run.

The existing child scope remains limited to the two manifest tables, their approved Candidate relationships, required `os_sr_callout` Choice metadata, and approved keys/audit flags. Candidate create/replacement, Custom API, plug-in, roles, app/Site Map, publishing, and business records remain excluded.

## 14. Call Log Provisioning

Not attempted. Table-create writes: **0**.

## 15. Call Log Reconciliation

Not performed. Its fields, Choice linkage, Candidate lookup, relationship, key, audit flag, and Solution membership remain unverified for this run.

## 16. Status History Provisioning

Not attempted. Table-create writes: **0**.

## 17. Status History Reconciliation

Not performed. Its fields, status Choice bindings, Candidate lookup, relationship, key, audit flag, and Solution membership remain unverified for this run.

## 18. Relationship Reconciliation

The fresh Candidate reconciliation verified the three existing Candidate reference relationships and their inclusion through the Candidate root. The current manifest defines five relationships total:

- Candidate → Call Log: `os_sr_cand_call`, lookup `os_sr_call_cand`.
- Candidate → Candidate Status History: `os_sr_cand_csh`, lookup `os_sr_csh_cand`.
- Position → Candidate: `os_sr_pos_cand`.
- Candidate Source → Candidate: `os_sr_csrc_cand`.
- TA Directory → Candidate: `os_sr_ta_cand`.

The two child-to-Candidate relationships specify Delete Restrict and no Assign/Share/Reparent cascade, but they were not created or reconciled. The manifest has required Call Log Contacted By and Status History Actor lookups to `systemuser` without corresponding relationship schema names. The five-item count is sourced from the current manifest; no additional custom names were inferred.

## 19. Choice Freeze

No `os_sr_callout` Choice was created or read. The current manifest provides the exact labels Answered, No Answer, and Call Back Requested but leaves integer values unassigned. No manifest changes were made. If the Choice is created under a future authorized execution, Dataverse values must be GET-reconciled and frozen before Custom API/plugin implementation.

## 20. Final Manifest SHA

No live-assigned Choice values or verified metadata normalization occurred, so the manifest was not changed. Final SHA-256 remains:

`7cfe13bb7450946c17e3659e02a4b78aecfd93f50c272561b1e88c6084d566d1`

## 21. Full Candidate Core Storage State

The fresh read verified Candidate exact and Call Log/Candidate Status History absent. Because writes were blocked, the resulting three-table storage state was not provisioned. The `os_sr_callout` Choice was not checked and the two `systemuser` lookup relationships remain unspecified in the manifest.

## 22. Deferred Custom API / Security Scope

No Custom API, plug-in, Execute privilege, role, app, Site Map, form/view, scheduling, Outlook, Teams, email flow, LEGO Career, or Candidate business-record operation was performed.

Status for handover: **`API_PRIVILEGE_READY_FOR_NEXT_PHASE_REVIEW`**. Candidate is now freshly verified to exist, so API privilege design may be reviewed in a later phase. It does not mean that an API privilege was inspected, validated, or approved. No final API security validation was done here.

## 23. Request / Write Counts

| Operation | Count |
|---|---:|
| GET | 31 |
| Table-create writes | 0 |
| Attribute writes | 0 |
| Choice writes | 0 |
| Relationship writes | 0 |
| Key writes | 0 |
| Candidate create / update / destructive writes | 0 |
| Business-data writes | 0 |
| App / Site Map writes | 0 |
| `PublishXml` | 0 |
| `PublishAllXml` | 0 |
| Retries | 0 |
| **All tenant requests** | **31 GET / 0 POST** |

## 24. No-Retry Proof

Thirty-one read-only GETs were completed in the guarded reconciliation process. No POST or other write was dispatched; retries were **0**. There was no uncertain write outcome.

## 25. Regression Results

| Check | Result |
|---|---|
| Phase 3A design / current manifest suite | PASS — 43 synthetic assertions |
| Candidate reconciliation | PASS — 31 GET guarded reconciliation; exact Candidate schema, Choice mapping, keys, relationships, and Solution inclusion |
| Child-table, Call Outcome Choice, systemuser relationship, idempotency, and child audit live checks | NOT RUN / BLOCKED before writes |
| Reference provisioning suite | PASS — 550 synthetic assertions |
| Readiness suite | PASS — 11 synthetic assertions |
| App composition suite | PASS — 329 synthetic assertions |
| Privacy scan of report and newly added Current State lines | PASS — no email addresses, absolute URLs, bearer tokens, secret assignments, or GUID identifiers |
| Relative Markdown links in this report | PASS |
| PowerShell parser | PASS — provisioning runner and four test scripts, 0 diagnostics |
| `git diff --check` and untracked-report whitespace | PASS |

Synthetic tests validate local proposal/regression behavior only; they are not a substitute for live Candidate reconciliation or metadata provisioning.

## 26. Files Changed

This disposition updates this report and [Current State](CURRENT_STATE.md) only. The manifest and Candidate-only runner were not changed. No live environment component was changed.

## 27. Final Classification

**`PRE_WRITE_GATE_BLOCKED`**. The resumed target and identity guards passed, and Candidate reconciled exactly. The current manifest lacks stable relationship schema names for the required `systemuser` lookups; the existing Candidate-only runner cannot provision these child tables. The Call Outcome Choice was not freshly preflighted. No write was dispatched.

## 28. Exact Recommended Next Task

Resolve stable relationship schema names for the required `systemuser` lookups in the manifest, or document a supported Dataverse-generated naming method and its exact readback acceptance criteria. Then use a child-table-only guarded runner with a fixed write allowlist, zero retries, and immediate readback. Freshly inspect `os_sr_callout` and the full existing schema in the same guarded process immediately before any write. Do not weaken or repurpose the Candidate-only runner.

## 29. AI HANDOVER

- Current manifest SHA-256: `7cfe13bb7450946c17e3659e02a4b78aecfd93f50c272561b1e88c6084d566d1`.
- Resumed target/credential/WhoAmI guards passed; expected-user process pin was established in the guarded process.
- Resumed Candidate reconciliation was exact (31 GET, 0 POST); both child tables were absent. `os_sr_callout` was not checked.
- Organization audit was freshly read as disabled; no organization setting was changed.
- Two systemuser lookup relationship schema names are missing from the current manifest, so no complete child-table write plan could be built.
- The existing runner is Candidate-only and explicitly excludes the two child tables.
- No tenant writes, Candidate changes, business data, app changes, publication, or retries occurred.
- No commit or push occurred.
