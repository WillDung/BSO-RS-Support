# Phase 5A Candidate Core acceptance - 28 October 2026

## Result and scope

Authenticated Candidate Management browser acceptance passed in exact `srapp` in **VN LMV IT only**, using synthetic candidates and reserved `.invalid` email addresses. Production is the target architecture, not the environment tested.

```text
PHASE_5A_CANDIDATE_CORE_PRODUCTION_PATH_WORKING_IN_DEV
CANDIDATE_MANAGEMENT_USING_CUSTOM_API
SCHEDULING_EVIDENCE_CONTRACT_RESOLVED
BSO_EXECUTE_PRIVILEGE_RESOLVED
PROTECTCANDIDATECORE_SUPERSEDED
DIRECT_WRITE_SECURITY_TARGET=DATAVERSE_ROLE
BSO_PRODUCTION_ROLE_READY_UNASSIGNED
REAL_DATA_STILL_PROHIBITED
PHASE_5B_BSO_ROLE_ASSIGNMENT_APPROVAL_REQUIRED
```

These results establish the privileged DEV identity's functional path, not effective BSO-user security or Production acceptance. Phase 5B has not started.

## Browser evidence

The page visibly displayed `CANDIDATE CORE PATH`; the explicit DEV direct-write fallback remained unchecked throughout acceptance and after reloads. Each submitted business operation was observed as a POST to `os_sr_cact` returning HTTP 200. Requests were not intercepted, altered, or resent. No automatic fallback was used.

| Branch | Synthetic Candidate | Browser operations and persisted result | Calls | History | Schedules | Receipts |
|---|---|---|---:|---:|---:|---:|
| A - Pass | `CAND-00001040` | Create generated number and Need Call; No Answer added a call without transition; Answered added the second call and status history; Waiting; Schedule; Pass -> Offer Extended | 2 | 4 | 1 | 6 |
| B - Fail | `CAND-00001041` | Create; Answered; Waiting; Schedule; Fail -> Candidate Failed | 1 | 4 | 1 | 5 |
| C - corrected reschedule | `CAND-00001043` | Create; Answered; Waiting; Schedule; Reschedule -> Need Call; Answered; Waiting; reconfirm Proposed replacement -> Round 1 Scheduled | 2 | 7 | 2 | 8 |
| D - Cancel | `CAND-00001044` | Create; Answered; Waiting; Schedule; Cancel -> Need Call Candidate | 1 | 4 | 1 | 5 |
| **Accepted scope** | **4 Candidates** | **24 successful API operations** | **6** | **19** | **5** | **24** |

- A's schedule remained visible after a full browser reload before recording Pass. A's Pass, result timestamp, terminal Candidate status, schedule, and terminal history persisted after a second full reload.
- B's Fail, result timestamp, Candidate Failed state, schedule, and history persisted after full reload.
- C's old schedule remained Superseded, with the synthetic reschedule reason and lifecycle timestamp visible. The replacement was first Proposed while Candidate returned to Need Call Candidate. Re-contact and explicit scheduling promoted that same replacement to Scheduled. After full reload, exactly two schedule rows remained: historical Superseded and current Scheduled, with Candidate Round 1 Scheduled and history visible.
- D's Cancelled row, synthetic cancellation reason, lifecycle timestamp, Need Call Candidate status, and history persisted after full reload.
- Scheduling used existing `[DEV] Synthetic Interviewer` and `[DEV] Test Location` references. These durable records prove manual workflow evidence, not calendar availability or booking.
- Read-only FetchXML reconciliation independently returned the per-candidate counts above. Receipt action rows matched the browser operations, including RequestReschedule and CancelRound1.

## Observed failure and bounded correction

The first C fixture, `CAND-00001042`, completed Create, Answered, Waiting, and Schedule. Opening Reschedule displayed its draft but Save Schedule remained disabled. The click timed out before submission: **no RequestReschedule request reached `os_sr_cact`**, and no API error category was returned. Read-only reconciliation found Round 1 Scheduled, one call, three histories, one active Pending schedule, and four receipts. This fixture remains intact, excluded from accepted-branch counts, and was not retried or compensated.

The deterministic defect was local to the console: `setBusy(false)` applied new-schedule eligibility to Save Schedule even in reschedule mode. The correction uses `canManageSchedule()` in reschedule mode and recomputes button availability when opening a scheduling draft. Existing busy, synthetic-candidate, pending-result, active-schedule, and retry-block gates remain. No business semantics, request construction, Candidate Core source, or guard logic changed.

Focused checks passed before publication. The existing console HTML and JavaScript were refreshed using two web-resource PATCHes, zero Site Map PATCHes, one app/resource-scoped PublishXml, and published-resource GET reconciliation. CSS was unchanged. Browser readback confirmed script `b3cb9041e448` before the fresh C fixture was created. Only the failed branch was rerun; A and B were not duplicated.

Including the stopped C fixture, this browser run created **5 Candidates / 7 Calls / 22 Histories / 6 Schedules / 28 Receipts**. These are separate from runner fixtures and earlier phases.

## Replay and runtime reconciliation

After browser acceptance, the existing [Phase 5A runner](../scripts/Test-BsoRsCandidateCorePhase5A.ps1) ran PlanOnly, then its unchanged bounded Apply matrix against fresh synthetic fixtures:

- PlanOnly: `PHASE_5A_RUNTIME_PREFLIGHT_READY`; 43 GETs, zero POSTs, zero candidate/email/receipt collisions; 18 declared inputs; execute privilege `prvReados_sr_cand`.
- Apply: `PHASE_5A_CANDIDATE_CORE_RUNTIME_MATRIX_PASSED`; 27 dispatches, 83 GETs, zero automatic retries.
- Durable runner-only counts: **4 Candidates / 6 Calls / 16 Histories / 5 Schedules / 22 Receipts**.
- Identical replay returned `DuplicateReplay` without duplicate business effects; conflicting replay and stale ExpectedStatus were deterministically rejected.
- Runner final states: A Offer Extended; B Candidate Failed; C and D Need Call Candidate.

Local session evidence is retained as `phase5a-post-browser-runtime-20261028.json` and `candidate-console-reschedule-gate-refresh-20261028.json`. These journals are not solution exports and contain no claim of deployed package byte equivalence.

## Local validation

The following checks ran after the correction:

- `tests\CandidateConsole.Tests.ps1`: **51 static assertions passed**, including reschedule-mode Save Schedule gating and draft-open availability recomputation.
- `node --check solutions\CandidateConsole\WebResources\os_\bso\candidate-console.js`: passed.
- `tests\Phase5ACandidateCoreRuntime.Tests.ps1`: **19 offline assertions passed**.
- `tests\Phase5ASecurityBoundary.Tests.ps1`: **10 synthetic assertions passed**.
- PowerShell parser: **35 scripts passed** across scripts/tests.
- Relative-link validation: **139 local targets passed** across the six updated status/security/UI/runtime/source documents.
- Scoped privacy scan of added tracked lines and this report: no detected private keys, bearer tokens, credential assignments, or non-synthetic emails. This bounded scan is not a comprehensive privacy certification.
- `git diff --check`: passed.

Candidate Core C# source was unchanged in this continuation, so engine/SDK suites and package rebuild were not rerun. Their earlier Phase 5A evidence remains separate from the console regression and live browser proof.

## Role and Phase 5B boundary

Read-only role reconciliation confirmed `BSO-RS Support - BSO` has **zero user assignments and zero team assignments**. Its custom-table privilege list is:

| Scope | Observed privileges |
|---|---|
| Candidate, Call Log, Status History, Interview Schedule | Read, Append, Append To at Basic; no Create, Write, Delete, Assign, or Share |
| TA, Position, Candidate Source, Location | Read at Organization |
| Operation Receipt | No custom-table grants |
| Candidate Core execution | `prvReados_sr_cand`, matching live ExecutePrivilegeName |

This reuses the existing Candidate Read privilege; it is not a new dedicated privilege object. No broad administration/customization/publish grants or role memberships were added. Historical platform defaults still require Phase 5B review. The role-level model denies direct protected-table writes, but actual user-context denial, app access, and role usability are **not tested** here.

The exact Phase 5B test account is not designated by this acceptance. Owner approval must identify that account and authorize assignment separately; no account or app-sharing grant is inferred. Expected future access is Candidate Management in `srapp` through Candidate Core, subject to app sharing and effective role validation. Do not assign a real user/team or start Phase 5B automatically.

`ProtectCandidateCore` remains superseded with registrations inactive; no guard, marker, ParentContext, Profiler, or PluginTraceLog diagnostics were reopened. No Candidate Core package update was required in this browser continuation. No Production access, real data, new PluginPackage, signing key, legacy assembly change, PublishAllXml, commit, or push occurred.

See [Current State](CURRENT_STATE.md), [Security Model](SECURITY_MODEL.md), and [Candidate UI implementation note](CANDIDATE_UI_IMPLEMENTATION_NOTE.md).
