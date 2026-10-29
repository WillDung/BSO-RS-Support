# Phase 5B role assignment and security acceptance - 28 October 2026

## 29 October 2026 continuation - Receipt ownership defect proven; local correction validated

**Current status:** `PHASE_5B_RECEIPT_OWNERSHIP_FIX_LOCAL_VALIDATED_NOT_DEPLOYED`; Phase 5B is not accepted. Static inspection confirmed that the `CreateReceipt` Entity passed to the SYSTEM storage service explicitly set `ownerid` to the initiating BSO user. The live stage was `RECEIPT_CREATE:0x80040299` (`TargetPrincipalLacksReadPrivilege`), matching that caller-owned target on a UserOwned infrastructure table. No Receipt privilege was granted.

The local correction removes only the explicit Receipt `ownerid` assignment and no longer reads Receipt owner as actor attribution. The initiating actor remains included in the existing versioned request fingerprint, so identical replay remains actor-bound and conflicting replay remains rejected. Candidate ownership remains the initiating BSO user; existing explicit actor fields on Call Log, Status History, scheduling, and result evidence were not changed. The Receipt remains append-only with no Update operation.

Validation passed: engine 177; SDK/storage/SYSTEM-boundary 346; Receipt plan/idempotency 27; Phase 5A runtime/API-input/security suites 19/9/10; Phase 5B security suite 12; unsigned package integrity 12; PowerShell parsing 19 scripts. The rebuilt local package remains unsigned. At report time, no package update or post-fix runtime call had occurred; no Phase 5B pass or lifecycle/direct-write acceptance is claimed. `REAL_DATA_STILL_PROHIBITED`.

## 29 October 2026 continuation - Candidate Console refreshed; Receipt create failure localized

**Current status:** `PHASE_5B_CANDIDATE_CORE_FAILURE:RECEIPT_CREATE`; sanitized Dataverse code `0x80040299`. This is not a Phase 5B pass.

The local parser already recognized the safe Candidate Core stage format, but the live HTML still referenced the previous JavaScript cache token. The existing scoped Candidate Console refresh workflow first patched only `os_/bso/candidate-console.js`, then patched only `os_/bso/candidate-console.html` after reload proved its served token stale. Each exact resource was patched once and published in a separate scoped `PublishXml` alongside `srapp`; published GET readback reconciled each. No package, sitemap, schema, role, guard, or other resource changes occurred; retries were zero. The current JS SHA-256 is `82a252c25d5c33b557ff41a8b339f3879c6dff3d7d54f53bf8cba43c7f138ea4`; the HTML cache token is `82a252c25d5c`.

A cache-bypassing reload of exact `srapp` confirmed the HTML requested the matching JS, the returned JS bytes matched the local full SHA-256, Candidate Core was active, DEV fallback was off, and fresh WhoAmI matched VN LMV IT. Exactly one fresh synthetic CreateCandidate was submitted. It returned HTTP 400 / `0x80040265`; the sanitized response contained only top-level `error` with `code` and `message`. An allowlisted match from `error.message` was `RECEIPT_CREATE:0x80040299`, and the updated UI surfaced that stage/code without raw fault text.

Read-only aggregate reconciliation for this synthetic attempt found **0 Candidates / 0 Call Logs / 0 Status Histories / 0 Interview Schedules / 0 related Operation Receipts**. The existing Receipt schema/key and Candidate Core contract reconciled exactly with zero writes. Source review confirms the `CreateReceipt` payload corresponds to the documented Receipt columns, but the stage/code and available evidence do not prove a deterministic source defect. No package update, second Candidate Core call, lifecycle continuation, or direct-write negative test is authorized by the evidence in this continuation. Phase 5B remains blocked; real data remains prohibited and Production deployment remains out of scope.

## 29 October 2026 continuation - safe-stage correction deployment and stop

**Current status:** `PHASE_5B_CANDIDATE_CORE_FAILURE:SAFE_STAGE_UNAVAILABLE`; this is not a Phase 5B pass. Local Candidate Core changes classify CreateCandidate failures as `CANDIDATE_CORE_OPERATION_REJECTED:CREATE_CANDIDATE:<STAGE>:<SANITIZED_CODE>`, including input and reference validation as well as Receipt read, Candidate create/readback, Receipt create, and response. The Candidate Console parser was updated locally to understand that shape, and SDK regressions were added. The web resource itself was not deployed.

After local validation, the existing unsigned `os_sr_cact_pkg` v1.0.0 was updated once with PAC CLI `pac plugin push`; retries were zero. PAC returned success. The package identity/version remained the same and its `ModifiedOn` advanced. Immediate GET-only reconciliation confirmed the same package-backed File Store assembly and `ApplyCandidateAction` type, the same Custom API handler relationship and contract metadata, all 50 `ProtectCandidateCore` registrations Disabled, PluginTraceLog Off, no active Candidate Core Profiler wrapper, and the separate signed Database rollback assembly unchanged. Package bytes were not exposed for server-side hashing. Local artifact SHA-256 values: package `64b3212e38d72296f07b57f7f4c12e3ae4b3b2cbed72bf4510b47eef5aeaeebd`; embedded and built DLL `eaa124d4a9a1cdb2cb3372ee8bae4c5ac244e0ef4f7bb46aa236d11e2c3acb79`.

The already-open exact `srapp` browser page remained on Candidate Management; a fresh browser WhoAmI returned HTTP 200 for VN LMV IT. Candidate Core remained active and DEV direct-write fallback was unchecked. Exactly one new fresh synthetic CreateCandidate was submitted after deployment. It returned HTTP 400 / `0x80040265`. The visible console still reported only `CANDIDATE_CORE_CreateCandidate_FAILED:0x80040265`; no safe internal stage was surfaced. The Candidate list refreshed without showing the synthetic record. No further Candidate Core call, lifecycle continuation, receipt check, or direct-write negative test followed. Do not infer the failing internal stage from `0x80040265`; no deterministic storage defect is proven. Phase 5B remains pending, real data remains prohibited, and Production deployment remains out of scope.

## 29 October 2026 continuation - existing unsigned package deployed; Candidate Core acceptance blocked

**Current status:** `PHASE_5B_SECURITY_ACCEPTANCE_PENDING`; not a security pass. Fresh PAC identity verification matched VN LMV IT. Read-only topology reconciliation found exactly one existing `os_sr_cact_pkg` v1.0.0; the active `os_sr_cact` Custom API handler remained `os_sr_cact.ApplyCandidateAction` in its package-backed File Store assembly with an empty public-key token. The separate signed Database assembly remained the rollback artifact and was not modified.

The existing package was updated once with the locally rebuilt unsigned artifact. An initial PAC command used a nonexistent package ID and returned before an update; after a fresh exact-name lookup, the single valid update succeeded. The existing package identity/version remained unchanged and its `ModifiedOn` advanced from 28 to 29 October 2026. The active handler relationship and Custom API metadata remained unchanged. The local package SHA-256 is `758adef7e3a3704e4e500c6cf19d493f0840e0c853a6055dcfa43854cbb85c44`; the embedded and current Release DLL SHA-256 is `74c1c0642159a38d5c703ad16fd5485a9a50adab0238b34207418f87c84a1ed4`. Dataverse package bytes were not required for reconciliation. All **50/50** `ProtectCandidateCore` registrations remained Disabled. Organization PluginTraceLog remained Off; no active Plugin Profiler wrapper was found. No signing key was inspected or used.

The exact `srapp` browser session returned WhoAmI HTTP 200 for the BSO-role test identity and VN LMV IT. The user had the BSO direct role and only the default owner team. Candidate Management loaded with Candidate Core active and the DEV direct-write fallback unchecked; Position and Candidate Source selectors loaded.

Exactly one fresh synthetic CreateCandidate request was sent through Candidate Management / `os_sr_cact`. It returned HTTP 400 / `0x80040265`. The browser console exposed `CANDIDATE_CORE_CreateCandidate_FAILED` but did **not** expose an allowlisted internal stage or sanitized stage category. The UI refreshed its candidate list and showed no synthetic candidate. No retry occurred. Per the stop rule, no further Candidate action was attempted: Answered, Waiting Manual Scheduling, Round 1 scheduling, receipt verification, TA/Location selector verification, and all five direct-write negatives remain unperformed. Phase 5B is blocked at the Candidate Core CreateCandidate runtime gate, not accepted. Real data remains prohibited; no Production work, role changes, commit, or push occurred.

## 29 October 2026 continuation - Candidate Core storage boundary (predeployment audit)

**Current status:** `PHASE_5B_SECURITY_ACCEPTANCE_PENDING`. The approved BSO identity can reach Candidate Management in exact `srapp`. The BSO role retains the App Opener baseline and Candidate Core execute privilege; no protected-table Create/Write/Delete or Operation Receipt privileges were granted. `ProtectCandidateCore` remains inactive. No additional role, app, or team changes occurred.

One synthetic Candidate Core CreateCandidate call returned HTTP 400 / `0x80040265`. Read-only reconciliation found **0 Candidates / 0 Call Logs / 0 Status Histories / 0 Interview Schedules / 0 CreateCandidate Receipts** for the attempt. The call was not retried. No direct-write negative tests were run.

### Static source audit

| Operation stage | Table | Access | Organization service | Identity |
|---|---|---|---|---|
| CreateCandidate: receipt lookup | Operation Receipt | Read | `systemService` | SYSTEM |
| CreateCandidate: Candidate persistence | Candidate | Write | `systemService` | SYSTEM |
| CreateCandidate: handler Candidate readback | None | None | None | None |
| CreateCandidate: receipt persistence | Operation Receipt | Write | `systemService` | SYSTEM |
| Operation Receipt update | Operation Receipt | Update | No supported Candidate Core path | Not applicable; receipts are append-only |
| Other operation/replay: candidate state | Candidate | Read | `callerService` in audited source | Initiating user |
| Scheduling/result/reschedule/cancel: schedule query/readback | Interview Schedule | Read | `callerService` in audited source | Initiating user |
| Candidate, Call Log, Status History, Interview Schedule, Receipt mutations | Protected tables | Write | `systemService` | SYSTEM |
| Position/Source/TA/Location validation | Reference tables | Read | `callerService` | Initiating user |

The Candidate Core SDK adapter is the `CandidateCore.Package.csproj` that links `DataversePlugin.cs` and `Operation.cs`; the local `DataverseStore` is the Receipt store and Candidate/schedule repository. No separate adapter or repository implementation was found.

`CANDIDATE_CORE_CALLER_CONTEXT_STORAGE_DEFECT_PROVEN`. The local source correction moves protected Candidate and Interview Schedule reads/readbacks to `systemService`. Candidate access is checked through SYSTEM `RetrievePrincipalAccess` before retrieval; schedule lookup first reads IDs only, checks initiating-user `ReadAccess` for each ID, then retrieves schedule details through SYSTEM. Reference validation remains caller-context. Candidate, Call, History, Schedule, and Receipt writes remain SYSTEM; owner and actor fields remain the initiating user; Candidate Number is not supplied by the plug-in and remains server-generated. The immutable ActionType-to-mutation matrix is unchanged and no caller-provided entity/table/attribute can select a SYSTEM write.

CreateCandidate stage failures now produce only `CANDIDATE_CORE_OPERATION_REJECTED:<STAGE>:<CODE_OR_CATEGORY>`, with stage restricted to `RECEIPT_READ`, `CANDIDATE_CREATE`, `CANDIDATE_READBACK`, `RECEIPT_CREATE`, or `RESPONSE`. The console extracts and displays/logs only that allowlisted diagnostic; raw response text is not logged.

### Validation and deployment disposition

- Candidate Core engine tests: **177 passed**.
- Candidate Core SDK adapter/storage tests: **335 passed**.
- Candidate Console checks: **52 passed**.
- Phase 5A API-input/runtime/security boundary checks: **9 / 19 / 10 passed**.
- Phase 3C Receipt/deployment checks: **27 / 31 passed**.
- Phase 3D-R4 package/deployment checks: **12 / 29 passed**.
- Unsigned `CandidateCore.Package.csproj` build: **passed**, version `1.0.0.0`, no strong-name public key.

At the time of this predeployment audit, the active handler was incorrectly believed to be the signed Database assembly. Later live topology reconciliation showed that the active handler was already package-backed by the existing unsigned File Store package, so signing-key availability was not a blocker. The package update and one synthetic diagnostic attempt are recorded in the current section above. Phase 5B remains pending; the live CreateCandidate failure is not resolved and no direct-write negative test has been performed.

## 29 October 2026 continuation - App Opener read baseline and gateway block

**Current status:** `PHASE_5B_SECURITY_ACCEPTANCE_PENDING`. This update follows the 29 October approved-identity assignment record below. It does not claim Phase 5B acceptance.

The approved browser session returned WhoAmI for the exact approved Dataverse user and VN LMV IT organization. No credentials were requested, captured, or stored.

### Read-only App Opener comparison

Live `RetrieveRolePrivilegesRole` inspection found **81** privileges on the predefined App Opener role and **25** on `BSO-RS Support - BSO` before correction. The BSO role lacked **72** entries from the App Opener set: **35 read-only** and **37 non-read/mutating** entries. The user-directed scope excluded workflow/process and other mutating privileges, customization/create/write/delete, publish, solution/role administration, environment administration, and unrelated business-table privileges.

The browser successively reported these exact missing App Opener baseline privileges:

| Privilege | Browser required depth | App Opener depth | BSO correction |
|---|---|---|---|
| `prvReadEntity` | Basic | Global | Added at Global |
| `prvReadAttribute` | Basic | Global | Added at Global |
| `prvReadRelationship` | Basic | Global | Added at Global |

Each was absent from BSO and present on App Opener before its one-shot addition. Each `AddPrivilegesRole` invocation returned HTTP 204, used zero retries, and had readback confirming Global depth. The `prvReadRelationship` denial cleared after reload. Effective privileges increased to 28 and include the three read privileges.

Final role/effective-access readback confirms:

- The approved identity has only the BSO role directly and remains in only its default owner team.
- `srapp` already associates BSO; System Administrator/System Customizer associations remain unchanged and do not imply those roles are held by this identity.
- BSO has no Candidate, Call Log, Status History, or Interview Schedule Create/Write privilege.
- No effective customization/publish-write, role administration, or protected business-write conflicts were detected.
- No additional user/team role, app association, or membership change occurred.

### Browser result and remaining gates

After the three observed privilege corrections, later bounded reloads continued returning HTTP 502 during model-driven metadata retrieval; the latest browser log at 09:22:54 identified `GetClientMetadata`. No new specific denial was observed in the bootstrap error, so no additional App Opener privileges were granted. The app did not finish loading. Candidate Core path and fallback state, the synthetic positive lifecycle, reference-selector reads, the five direct-write negatives, and acceptance-scope reconciliation were not performed. No Candidate or other business record was created. This is not evidence of Candidate-table Read denial and not a Phase 5B security pass.

### 29 October 2026 read-only isolation diagnostics

The shared browser remained on the exact approved `srapp` URL and was the same previously validated test-account session. A later reload reproduced the `AppContextLoader` / `GetClientMetadata` HTTP 502 at 09:22:54 local time. The visible details contained a generic IIS-style gateway error page and the UCI `AppContextLoader` stack; browser tooling did not expose the failing network response event, so the exact failing request host/path category, response content type/headers, Microsoft request identifiers, and request timing were not captured. The console shows the failure about 0.9 seconds after reload began, which is not an authoritative request-duration measurement.

Read-only same-session endpoint checks:

| Check | Result | Interpretation |
|---|---|---|
| Dataverse `WhoAmI` | HTTP 200, JSON with expected response shape | Authenticated Dataverse data-plane reachability works in this browser session; no business write was made. |
| Filtered app-module list for `srapp` | HTTP 200, JSON; app not returned | The app was not visible through this list query; this alone does not establish app absence. |
| GET exact app module | HTTP 403, Dataverse error `0x80040220`, names `prvReadAppModule` | A distinct app-module metadata read is denied to this identity. It is not proven to be the cause of `GetClientMetadata` 502. |
| GET app role associations | HTTP 403 | No role-association contents were obtained; the prior verified app association was not changed. |

No InPrivate/Incognito or alternate-browser context, alternate corporate network path, or separately authenticated administrator control session was available in the shared browser tools. Therefore neither `502_REPRODUCES_ACROSS_CLEAN_BROWSER_CONTEXTS`, `502_BROWSER_CACHE_SPECIFIC`, `SRAPP_METADATA_PLATFORM_OR_NETWORK_BLOCKER`, nor `SRAPP_METADATA_USER_CONTEXT_BLOCKER` is established. The exact-appmodule `prvReadAppModule` denial warrants read-only comparison with the live App Opener baseline and effective BSO role only after the same-app administrator control is available; **no privilege correction is authorized or made based on the 502**. No role, app, package, guard, Candidate Core, or data state was changed.

Continue only when the exact `srapp` browser can load under the approved identity. If a new explicit missing privilege is then reported, compare it with live App Opener and grant only that exact baseline privilege at matching depth if within the approved non-mutating scope. Preserve the no-direct-write invariant. Exact identity is not recorded in this repository; real data and Production deployment remain prohibited.

## 29 October 2026 continuation - browser authentication pending

**Current status:** `PHASE_5B_BROWSER_ACCEPTANCE_PENDING_MANUAL_IDENTITY_AUTH`. This continuation does not pass Phase 5B and supersedes neither the historical 28 October evidence below nor its security conclusions for the prior approved account.

The owner newly approved a second test identity for VN LMV IT. Exact identity is kept out of this repository; no credentials were requested, captured, or stored. Fresh pre-assignment inventory resolved one enabled, licensed, interactive system user in the BSO role's Business Unit. It had no direct roles, only its default owner team, and no conflicting effective customization, publishing, role-administration, or protected Candidate/Call/History/Schedule Create/Write privileges.

The existing `BSO-RS Support - BSO` role was assigned directly once with PAC; retries were zero. Immediate Dataverse readback confirmed the direct assignment. Post-assignment role inventory showed that role as the only direct role and no additional team roles; read-only effective privilege inspection found no conflicting privilege names. `srapp` already included the BSO role alongside its pre-existing System Administrator and System Customizer app associations, so this continuation made no app-association write and did not publish.

The integrated browser opened at Microsoft sign-in. Manual authentication by the approved test identity was not completed because the owner was unavailable to respond. Consequently, browser WhoAmI, `CANDIDATE CORE PATH`/fallback state under that identity, synthetic Candidate lifecycle, reference reads, direct Candidate/Call/History/Schedule negative requests, and acceptance-scope reconciliation were not performed. No direct-write result is claimed, and no other account or administrator session was used as a substitute. No additional user/team roles, memberships, privileges, app associations, or business data were changed.

The next required action is for the owner to manually authenticate the browser as the approved identity and confirm that exact `srapp` session is ready. Continue only after browser WhoAmI matches the approved system user. The existing approved scope remains VN LMV IT only; real data and Production deployment remain prohibited.

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
