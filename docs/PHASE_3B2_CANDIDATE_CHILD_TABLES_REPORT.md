# Phase 3B.2 — Candidate Child-Table Provisioning Disposition

**Date:** 24 October 2026  
**Final classification:** `BLOCKED_TARGET_CONFIRMATION`  
**Tenant requests / writes:** 0 / 0

## 1. Executive Summary

The owner explicitly authorized fresh read-only reconciliation of Candidate, followed only on an exact match by bounded creation of Call Log, Candidate Status History, and their manifest-approved schema. This work did not reach the environment. The current process has no environment URL or target identity pins, and the required exact organization URL / solution-container confirmation was not received. The user-unavailable response did not supply confirmation.

No PAC command, sign-in, token acquisition, Dataverse request, or metadata write was performed. This report does not claim that Candidate or either child table was freshly inspected on 24 October.

## 2. Preflight and Repository State

The requested outcome was to reconcile existing Candidate against the current repository manifest and, only if exact, provision the two remaining child tables within explicit scope limits. Local review found:

- The current manifest is `docs/PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json`; its SHA-256 is `7cfe13bb7450946c17e3659e02a4b78aecfd93f50c272561b1e88c6084d566d1`.
- Existing documentation records the 23 October Candidate schema reconciliation and that the Candidate creation authorization is consumed. It also records organization-level auditing disabled; the requirement is table-audit metadata, not an organization-setting change.
- The checked-in `scripts/Provision-BsoRsCandidateTable.ps1` is specifically Candidate-only. Its allowlist excludes `os_sr_call` and `os_sr_csh` and rejects their presence as outside its previous all-absent baseline. It is not a safe executor for Phase 3B.2.
- At the start of this request, the current process had no `BSO_RS_ENVIRONMENT_NAME`, `BSO_RS_ORG_URL`, expected environment/organization/user identity pins, or `SOLUTION_NAME` values. Values were not printed.
- The repository was on `main` at `652157e62ea0af1c1cf0b67b80a88bd5586cda90`, matching `origin/main`. The worktree already contained the Phase 3B.1 disposition changes to [Current State](CURRENT_STATE.md) and an untracked [Phase 3B.1 report](PHASE_3B1_CANDIDATE_TABLE_FAST_TRACK_REPORT.md); they were left intact.

## 3. Target and Solution Confirmation

Existing project evidence identifies VN LMV IT and Solution `os_sr_bso_rs_support` with Publisher `os_bso_rs_support` and prefix `os`. These are historical references, not a fresh target confirmation. The required exact organization URL was not provided or confirmed for this run. The target and solution gate therefore remains blocked.

No environment lookup was attempted to discover or infer the missing confirmation. No active authentication profile was selected or changed.

## 4. Approved Local Schema Scope

The current manifest specifies the following tables:

| Table | Ownership | Audit metadata | Primary name |
|---|---|---|---|
| `os_sr_call` — Call Log | UserOwned | Enabled | `os_sr_call_ref`, AutoNumber `CALL-{SEQNUM:8}` |
| `os_sr_csh` — Candidate Status History | UserOwned | Enabled | `os_sr_csh_ref`, AutoNumber `HIST-{SEQNUM:8}` |

Call Log fields in the manifest: required Candidate lookup `os_sr_call_cand`, required Call Outcome Choice `os_sr_call_out`, required Contacted At `os_sr_call_ctat`, required Contacted By system-user lookup `os_sr_call_ctby`, optional Notes `os_sr_call_nts` (4,000), and operation-required Correlation ID `os_sr_call_corid`. Its alternate key is `os_sr_call_ak_cand_action` on Candidate plus Correlation ID.

Candidate Status History fields in the manifest: required Candidate lookup `os_sr_csh_cand`, required Previous Status `os_sr_csh_prevstat`, required New Status `os_sr_csh_newstat`, required Actor system-user lookup `os_sr_csh_actr`, required Changed At `os_sr_csh_chg`, reschedule-required Reason `os_sr_csh_rsn` (1,000), operation-required Correlation ID `os_sr_csh_corid`, and required Candidate Action `os_sr_csh_cact` (50). Its alternate key is `os_sr_csh_ak_cand_action` on Candidate plus Correlation ID.

Approved relationships are Candidate → Call Log (`os_sr_cand_call`, lookup `os_sr_call_cand`) and Candidate → Candidate Status History (`os_sr_cand_csh`, lookup `os_sr_csh_cand`), with Delete Restrict and no Assign/Share/Reparent cascade.

The Call Outcome global Choice is `os_sr_callout`, with exactly Answered, No Answer, and Call Back Requested. Values are not assigned in the current manifest; system-assigned values must be read back and frozen before future API/plugin work.

These are local manifest requirements only; no corresponding 24 October live state is asserted.

## 5. Execution Limits

No writes were planned or dispatched because the fresh Candidate gate and target identity were not reached.

| Operation | Current request |
|---|---:|
| Candidate create | 0 |
| Candidate destructive/replacement writes | 0 |
| Call Log / History metadata writes | 0 |
| Custom API / plug-in writes | 0 |
| Role / app / Site Map writes | 0 |
| PublishXml / PublishAllXml | 0 |
| Business-data writes | 0 |
| Retries | 0 |
| All tenant requests | 0 |

No manifest, provisioning script, or live metadata was changed. No commit or push occurred.

## 6. Risks and Validation Plan

The central risk is that the old Candidate-only runner cannot safely express the newly authorized two-table scope and must not be repurposed by weakening its Candidate exclusion checks. Once the exact target and container are confirmed, a bounded implementation must first establish identity, Solution/Publisher, and exact live Candidate state; then construct and fingerprint a fixed child-only plan with a zero-retry transport and POST allowlist. If Candidate differs materially, stop before any child-table write. Each creation must be followed by GET-only reconciliation. No Candidate create/update/delete, organization audit-setting change, publication, access change, business data, or automatic retry is permitted.

No validation claims for a new child-table runner are made; one was not created. The existing offline test suites do not establish child-table runtime behavior.

## 7. Exact Next Gate

Before any environment request, confirm the exact approved VN LMV IT organization URL and the existing Solution/Publisher container (`os_sr_bso_rs_support` / `os_bso_rs_support`, prefix `os`). After that, perform the newly authorized guarded run using the current manifest. Keep Candidate create/destructive writes at zero and stop before Call Log or History provisioning if Candidate reconciliation is not exact.
