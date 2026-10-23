# Phase 3A.1 — Candidate Core Product Decision Closure Report

**Date:** 23 October 2026  
**Final classification:** `BLOCKED_PRODUCT_DECISION`  
**Scope:** Owner-decision recording and local design review only. No tenant connection, metadata read/write, provisioning, business data, or Phase 2D change.

## 1. Executive Summary

Phase 3A.1 requested explicit owner decisions on eight schema-affecting topics. No owner-authored selections were received. The decision form's generic fallback text was not treated as a choice, approval, rejection, or deferral. In particular, no recommendation is marked accepted and no `DEFER / EXTERNAL DECISION` choice is attributed to the owner.

The Phase 3A proposal and metadata manifest remain unchanged. The prior classification **`BLOCKED_PRODUCT_DECISION`** remains in force. A proposal may be retained for review, but it is not a closed product decision and is not provisioning-ready.

## 2. Candidate Number Decision

**Owner decision:** Not recorded.  
**Status:** Open; no owner selection among `ACCEPT RECOMMENDATION`, `ACCEPT WITH CHANGE`, `REJECT`, or `DEFER / EXTERNAL DECISION`.

The Phase 3A recommendation remains a proposal for a server-generated, immutable, unique, non-PII Candidate Number. The exact format/prefix is not approved and must not be fixed in a schema write. The previous Candidate Number field/key proposal has not been revised.

## 3. Call Outcome Decision

**Owner decision:** Not recorded.  
**Status:** Open; no owner selection among the required decision categories.

The suggested initial set—Answered, No Answer, Call Back Requested—remains a proposal only. The transition rule that an answered call can advance a Candidate in `Need Call Candidate` is grounded in the canonical workflow; the outcome taxonomy and non-answer logging semantics remain unapproved. No unsupported outcomes are added.

## 4. Contact Requiredness Decision

### Candidate Email

**Owner decision:** Not recorded. The recommendation to require email at Candidate creation is not approved.

### Candidate Phone

**Owner decision:** Not recorded. The recommendation to leave phone optional initially is not approved.

The two requirements remain independent decisions. No requiredness change is applied to the Phase 3A proposal.

## 5. BSO Ownership Decision

**Owner decision:** Not recorded.  
**Status:** Open; no selection between `Owner = responsible BSO`, separate security owner and operational assignment, rejection, or deferral.

The proposal's UserOwned model and Owner-as-BSO simplification remain design proposals only. No duplicate Assigned BSO field is approved or added; TA remains a distinct interviewer/directory lookup, not an owner or approval role by default.

## 6. Reschedule Policy Decision

**Owner decision:** Not recorded on whether the reason is mandatory, optional, changed, rejected, or deferred.

The canonical reschedule transition remains `Round 1 Scheduled` → `Need Call Candidate` through an approved business action with cancellation attempt and audit. The proposed mandatory reason and later cancellation/reconciliation evidence are not owner-approved. Phase 3A does not implement calendar operations.

## 7. Privacy / Audit Decision

No owner or organizational governance selections were recorded for:

- Candidate table auditing.
- Call Log table auditing.
- Candidate Status History Dataverse auditing.
- Column security for Candidate contact fields.

The recommendations remain proposals only. Existing repository evidence says environment audit is disabled and the configured 30-day value is not an approved retention policy. No environment/table audit configuration was read or changed in this task. If IT/Compliance policy controls any of these decisions, obtain that external decision rather than infer an approval.

## 8. Operation Identity / Idempotency Decision

**Owner decision:** Not recorded. The caller-generated GUID correlation/idempotency recommendation is not approved.

The Phase 3A proposal still requires duplicate protection as a design principle, but exact key identity, uniqueness scope, and replay semantics are not owner-closed. Timestamp-based keys are not proposed. The metadata manifest and API inputs are unchanged.

## 9. LEGO Career Dependency Decision

**Owner decision:** Not recorded.  
**Status:** Open; no selection to defer the Candidate lookup, include it now, reject, or defer to another decision.

The current proposal's `os_sr_lgcar` lookup remains provisional and must not be provisioned. The lookup target is not among the four verified Phase 2D reference tables. No live dependency was checked.

## 10. Consolidated Owner Decisions

| # | Decision | Owner record |
|---:|---|---|
| 1 | Candidate Number policy | Not recorded; no category selected. |
| 2 | Call Outcome taxonomy | Not recorded; no category selected. |
| 3a | Candidate Email requiredness | Not recorded; no category selected. |
| 3b | Candidate Phone requiredness | Not recorded; no category selected. |
| 4 | BSO ownership/assignment | Not recorded; no category selected. |
| 5 | Reschedule reason/evidence | Not recorded; no category selected. |
| 6a | Candidate table audit | Not recorded; no category selected. |
| 6b | Call Log table audit | Not recorded; no category selected. |
| 6c | Status History table audit | Not recorded; no category selected. |
| 6d | Contact column security | Not recorded; no category selected. |
| 7 | Operation identity/idempotency | Not recorded; no category selected. |
| 8 | LEGO Career dependency | Not recorded; no category selected. |

For each item, the required owner vocabulary remains `ACCEPT RECOMMENDATION`, `ACCEPT WITH CHANGE`, `REJECT`, or `DEFER / EXTERNAL DECISION`. Silence and generic fallback text do not select any of them.

## 11. Candidate Schema Impact

**No change.** `os_sr_cand` remains an unprovisioned proposal. Candidate Number format/key, Email/Phone create-time requiredness, Owner semantics, and LEGO Career lookup remain unresolved. No field was added, removed, made required, or re-keyed.

## 12. Call Log Schema Impact

**No change.** `os_sr_call` remains an unprovisioned proposal. The outcome field and candidate-action idempotency design are unchanged. No fixed Choice taxonomy was created or approved.

## 13. Status History Schema Impact

**No change.** `os_sr_csh` remains an unprovisioned proposal. Its proposed previous/new status, actor, timestamp, reason, correlation/action fields and append-only business purpose remain subject to the unresolved transition-operation decisions. No Dataverse audit flag or metadata was changed.

## 14. Workflow Contract Impact

The canonical six statuses and permitted business path remain unchanged:

`Need Call Candidate` → `Candidate Answered` → `Waiting Manual Scheduling` → `Round 1 Scheduled` → `Offer Extended` or `Candidate Failed`.

Reschedule remains a conditional return from `Round 1 Scheduled` to `Need Call Candidate` through an approved action, with cancellation attempt and audit. No deprecated TA approval stage is introduced. Phase 3A.1 adds no calendar side effect or new transition.

## 15. Security / Privacy Impact

No security decision was approved. BSO remains the primary interactive actor; TA does not automatically gain Candidate access. Least-privilege, privacy minimization, no PII in logs/repository/tests, and governance review remain applicable. Candidate, Call Log, History, and operation privileges are not configured or asserted.

Because the task does not establish the applicable organizational audit/column-security policy, those decisions cannot be inferred from the suggested minimum. The owner must either select the proposal explicitly or identify the relevant IT/Compliance decision authority.

## 16. Revised Naming / Key Contract

**No revision was made.** Existing proposed names remain:

- Tables: `os_sr_cand`, `os_sr_call`, `os_sr_csh`.
- Choice: `os_sr_candstat`.
- Candidate operation: `os_sr_cact`.
- Candidate Number key: `os_sr_cand_ak_cnum` (conditional on an approved number policy).
- Call idempotency key: `os_sr_call_ak_cand_action`.
- History idempotency key: `os_sr_csh_ak_cand_action`.

These are proposals, not deployed names. The existing `os_sr_*` naming contract remains; no identifiers are double-prefixed or include personal information.

## 17. Revised Metadata Proposal

**No schema-affecting owner decisions were recorded; therefore no manifest changes are justified.** The existing [Phase 3A synthetic metadata proposal](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json) remains unchanged, with exact-byte SHA-256:

`37da1392b2cfbd4a2886aa07886b00831775cc73c5f7bd65333ad70ceb334c0d`

This is a local proposal-file fingerprint, not a Dataverse request fingerprint. The manifest remains explicitly unauthorized for provisioning. It must be revised only after actual owner decisions are recorded.

## 18. Revised Provisioning Sequence

**No sequence execution or schema revision.** Provisioning remains prohibited until:

1. The owner records a decision category and any replacement rule for each product decision.
2. IT/Compliance resolves any audit/privacy matters assigned to them.
3. The design is revised and offline assertions pass against the resolved choices.
4. A fresh bounded preflight validates the target, solution, publisher, and dependencies without switching environments or logging in.
5. Separate explicit authorization is supplied for each bounded metadata operation.

No phase 2D app change is in scope. No API/plugin implementation is included in this decision-only closeout.

## 19. Offline Test Results

The existing Phase 3A offline design suite was rerun against the unchanged proposal:

- `Phase3ACandidateCoreDesign.Tests.ps1`: **28 assertions passed**.
- Proposal manifest SHA-256 remained unchanged at the value in Section 17.
- No authentication, network, PAC, Dataverse, or business-record calls were made.

Passing tests validate the unchanged proposal shape only. They do not close owner decisions or establish provisioning readiness.

## 20. Remaining Open Decisions

All eight decision areas remain open: Candidate Number, Call Outcomes, Email requiredness, Phone requiredness, Owner/BSO assignment, reschedule reason/evidence, auditing and contact-column security, operation identity/idempotency, and LEGO Career dependency. Exact subquestions are recorded in Sections 2–9. External governance must be identified for audit/privacy decisions where organizational policy applies.

## 21. Files Changed

Phase 3A.1 changes:

- New [Phase 3A.1 decision-closure report](PHASE_3A1_CANDIDATE_CORE_DECISION_CLOSURE.md).
- Updated [Current State](CURRENT_STATE.md).
- Updated [Product Decisions](PRODUCT_DECISIONS.md).
- Updated [Phase 3A design report](PHASE_3A_CANDIDATE_CORE_DESIGN.md) to record that this follow-up did not close decisions.

The Phase 3A proposal manifest and offline test were not changed. Earlier uncommitted Phase 3A files/edits were preserved.

## 22. Tenant Request / Write Counts

| Operation | Count |
|---|---:|
| Dataverse / tenant connection | 0 |
| Dataverse GET / metadata reads | 0 |
| Metadata/schema writes | 0 |
| Candidate/business data reads or writes | 0 |
| Custom API / plug-in operations | 0 |
| PublishXml / PublishAllXml | 0 / 0 |
| App / component / Site Map changes | 0 |
| User / role / team / access changes | 0 |
| Audit / DLP / environment changes | 0 |
| Retries | 0 |

## 23. Final Classification

**`BLOCKED_PRODUCT_DECISION`**

The decision-gathering step did not yield owner-authored selections. The system-provided fallback instruction is not an owner decision and cannot close product or governance questions. No proposal changes were made, so readiness remains blocked.

## 24. Exact Recommended Next Task

Have the product owner complete the decision record in Sections 2–10 by selecting one of the required categories for each item and supplying exact replacement rules for every `ACCEPT WITH CHANGE`. Obtain IT/Compliance decisions for audit/privacy items if required by organizational policy. Then update the Phase 3A report/manifest, regenerate the manifest fingerprint, rerun the offline assertions, and reassess readiness. Do not provision until the resulting report is explicitly ready and separate bounded write authorization is supplied.

## 25. AI HANDOVER

- Phase 3A.1 did not receive owner-authored decision selections; silence/fallback text was not treated as approval or deferral.
- All eight blocker areas and the independent Email/Phone/audit sub-decisions remain open.
- The Phase 3A design and metadata manifest are unchanged; manifest SHA-256 is `37da1392b2cfbd4a2886aa07886b00831775cc73c5f7bd65333ad70ceb334c0d`.
- Canonical workflow and `os_sr_*` proposal names remain unchanged.
- No tenant connection, request, read, write, provisioning, publication, app change, or permission change occurred.
- Final classification remains `BLOCKED_PRODUCT_DECISION`.
- Next: collect explicit owner/IT decisions, then revise and test the proposal before a separately authorized provisioning phase.
