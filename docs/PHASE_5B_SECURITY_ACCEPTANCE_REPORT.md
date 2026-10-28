# Phase 5B role assignment and security acceptance - 28 October 2026

## Result

```text
BSO_SECURITY_ACCEPTANCE_BLOCKED_BY_PREEXISTING_ELEVATED_ACCESS
PHASE_5B_ROLE_ASSIGNED_SECURITY_ACCEPTANCE_BLOCKED_BY_ELEVATED_ACCESS
BSO_ROLE_ASSIGNED_TO_APPROVED_TEST_USER
REAL_DATA_STILL_PROHIBITED
```

**This is not a Phase 5B security pass.** Only the authorized blocked-branch subset was completed in VN LMV IT. No Production-readiness or deployment gate is opened.

The target was the single existing account explicitly approved by the owner in the 28 October Phase 5B instruction, referenced here as **approved Phase 5B test account**. Its exact UPN and identity agreement are retained in local session evidence (`phase5b-app-access-20261028.json`), not copied into repository documentation to avoid personal identifiers. No other user/team was assigned.

## Fresh identity and pre-assignment inventory

PAC and browser WhoAmI agreed on the approved account and VN LMV IT organization; organization URL, environment identity, enabled user, and Business Unit matched. User and `BSO-RS Support - BSO` role resolution were unambiguous. The BSO role was in the target user's Business Unit.

| Category | Fresh state before assignment |
|---|---|
| Direct user roles | None |
| Default owner team roles | None |
| Entra-backed group team, Dataverse team type 3 (Office group) | System Administrator and Basic User |
| Administrative effective access | System Administrator through that group team |
| Platform baseline | Basic User through the same group team |
| BSO direct assignment | Absent |

No existing role or team membership was removed or modified.

## Authorized changes and readback

1. Executed PAC `admin assign-user` once for the approved user, exact existing BSO role, and exact VN LMV IT URL. **Assignment invocations: 1; retries: 0.** PAC reported success; immediate server readback independently confirmed the exact direct BSO role association.
2. Read `srapp` role associations: only System Administrator and System Customizer were present initially.
3. Added only the existing `BSO-RS Support - BSO` role to the app's role association using one app-specific relationship POST. Immediate GET confirmed all three roles; existing roles were preserved. No app content or role privilege was changed. No publication was required for this access association; PublishXml and PublishAllXml counts were zero.
4. Post-change server inventory confirmed the direct BSO role and unchanged group-derived System Administrator/Basic User roles.

The [bounded inspection/app-access script](../scripts/Test-BsoRsPhase5BSecurity.ps1) defaults to read-only Inspect, validates identity, follows guarded pagination, requires a new local evidence path, reserves its one app association dispatch before sending it, uses zero transport retries, and checks association readback and preservation of existing app roles. It does not assign user roles, remove memberships, impersonate users, or perform security-negative business writes. The initial user-role assignment was a separate, single PAC invocation.

## Positive functional subset

The authenticated browser WhoAmI was rechecked after assignment and matched the approved target account, not an administrator surrogate. The account itself still inherited administrator rights.

Exact `srapp` Candidate Management showed `CANDIDATE CORE PATH`; DEV direct-write fallback remained off. Fresh synthetic Candidate `CAND-00001049` completed:

| Action | Observed API result | Persisted state |
|---|---|---|
| CreateCandidate | POST `os_sr_cact`, HTTP 200 | Generated number; Need Call Candidate |
| RecordCall = Answered | POST `os_sr_cact`, HTTP 200 | Candidate Answered; Call Log and History |
| ProceedToScheduling | POST `os_sr_cact`, HTTP 200 | Waiting Manual Scheduling; History |
| MarkRound1Scheduled | POST `os_sr_cact`, HTTP 200 | Round 1 Scheduled; durable Pending schedule and History |

Read-only reconciliation returned **1 Candidate / 1 Call / 3 Histories / 1 Interview Schedule / 4 Operation Receipts**. Call, history, and schedule were visible in the UI. No full Pass/Fail/Reschedule matrix was repeated.

TA Directory, Position, Candidate Source, and Location selectors loaded the existing synthetic reference values. These prove reads and functional access under the approved account's combined effective roles, **not BSO-only authorization**.

## Security-negative and administration checks

No direct-write negative was submitted because the effective-security gate failed before testing.

| Requested direct operation | Result |
|---|---|
| Candidate Create | NOT ATTEMPTED - elevated-access conflict |
| Candidate Update | NOT ATTEMPTED - elevated-access conflict |
| Call Log Create | NOT ATTEMPTED - elevated-access conflict |
| Status History Create | NOT ATTEMPTED - elevated-access conflict |
| Interview Schedule Create/Update | NOT ATTEMPTED - elevated-access conflict |

There are no claimed privilege-denial responses or negative-test rows. Functional success must not be attributed to the BSO role alone.

Read-only browser effective privilege metadata reported organization-depth access (SDK depth code 3) for `prvCreateEntity`, `prvWriteEntity`, `prvPublishCustomization`, `prvWriteAppModule`, `prvWriteSolution`, `prvCreateRole`, `prvWriteRole`, `prvCreateos_sr_cand`, and `prvWriteos_sr_cand`. Therefore inability to customize, publish, edit app components, assign roles, or direct-write Candidates cannot be established for this account. No destructive administration action was attempted. Tenant/environment-management denial was not independently tested; Dataverse administrator access is already sufficient to block clean least-privilege proof.

The browser's cached role list still showed System Administrator/Basic User, while fresh server association reads confirmed the newly assigned BSO role. Cached UI role metadata is not used as proof that the new direct assignment is missing.

## Boundaries and next gate

Final read-only script inspection reconfirmed the direct BSO assignment, unchanged inherited administrator/baseline roles, and the three app role associations. That inspection dispatched zero app writes and zero retries.

Validation completed:

- [Phase 5B offline security-script checks](../tests/Phase5BSecurity.Tests.ps1): **12 passed**. These static safety assertions do not constitute user-context negative security acceptance.
- PowerShell parsing: **37 scripts passed** across scripts/tests.
- Relative Markdown links: **141 local targets passed** across the five Phase 5B status/report documents.
- Scoped privacy scan: added tracked lines plus the new Phase 5B report, script, and test contained no detected private keys, literal bearer credentials, or non-synthetic email addresses. Exact approved identity remains local evidence only.
- `git diff --check`: passed.

The blocking source is **pre-existing team-derived System Administrator through an Entra-backed Office group team**, not the BSO role. That access was not removed, reduced, or reassigned. No permission change beyond the approved direct BSO assignment and its app association occurred.

`ProtectCandidateCore` remains superseded and inactive; no guard, marker, ParentContext, Profiler, or PluginTraceLog diagnostic was reopened. No package, signing key, legacy assembly, real candidate data, Production resource, commit, or push was involved. DEV fallback remains retained but unused.

Phase 5B cannot pass until a separately authorized acceptance context has no conflicting effective elevated/business-write privileges. This report does not authorize or request membership removal. Production deployment is not started.

See [Current State](CURRENT_STATE.md), [Project Context](PROJECT_CONTEXT.md), [Security Model](SECURITY_MODEL.md), [Candidate UI note](CANDIDATE_UI_IMPLEMENTATION_NOTE.md), and the [completed Phase 5A acceptance](PHASE_5A_CANDIDATE_CORE_ACCEPTANCE_REPORT.md).
