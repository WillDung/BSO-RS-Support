# Phase 3C - Candidate Core Custom API + Plug-in Report

Date: 24 October 2026. Current closeout supersedes the earlier 17:20 blocked disposition retained in Git history. Source: explicit 17:29 owner authorization of minimal durable Operation Receipt storage, current contracts, guarded live metadata reads, consumed dispatch journals, local builds, and offline tests.

## 1. Executive Summary

**`CANDIDATE_CORE_API_DEPLOYED_AUDIT_ACTIVATION_PENDING`**

The minimal Operation Receipt schema is provisioned and reconciled. The signed Candidate Core assembly, two types, 50 server write guards, private unbound `os_sr_cact` Action, 13 request parameters, and five response properties are deployed and GET-reconciled in the approved Solution. Full post-deployment reconciliation confirms exact registration/inventory, content hash, handler, execution privilege, calling-user steps, and Solution membership.

Organization auditing remains disabled. No business API was invoked, no Candidate workflow/receipt rows were created, no access was granted, and no app/publication change occurred. This is **metadata deployment acceptance**, not live transaction, non-admin authorization, or end-user workflow acceptance. Future booking/result/reschedule actions remain fail-closed.

## 2. Repository / Manifest Baseline

| Item | Evidence |
|---|---|
| Repository / branch | BSO-RS-Support / `main`; not legacy ATSugg |
| Workspace | Opened BSO-RS-Support repository; personal root-path segments omitted |
| Starting HEAD and local `origin/main` | `1a124f1157d160ea63a43678952755f893f5b91d` |
| Timestamp | `2026-10-24T17:27:27+07:00` |
| Starting worktree | Clean; prior documentation preserved in observed baseline commit |
| Current Candidate Core manifest | [Phase 3A manifest](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json), unchanged |
| Core manifest SHA-256 | `63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915` |
| Authorized receipt contract | [Operation Receipt plan](PHASE_3C_OPERATION_RECEIPT_PLAN.json) |
| Final receipt-plan SHA-256 | `f26116c87e62c3a2faeecdf5e0a63a0ceef20069bdb78d36d9386a73dfed2efc` |
| Frozen API contract | [API contract](PHASE_3C_API_CONTRACT.json) |
| API-contract SHA-256 | `a6f8295df1f72a160c0490b49d457d7c0a6d82e23a3fcac8f1a68aa66b6bbaa9` |

No fetch, reset, restore, stash, pull, rebase, branch switch, commit, or push. The local remote-tracking reference is not a claim of a fresh network fetch. The separate receipt/API manifests preserve the existing three-table manifest and its historical execution ledger.

## 3. Environment / Identity Guard

Every live runner used the owner-confirmed VN LMV IT organization, existing active PAC target, existing Az.Accounts delegated user credential, JWT audience/tenant/scope/expiry validation, WhoAmI, and process-scoped expected-user agreement. No login/context/environment switch occurred.

Solution `os_sr_bso_rs_support` is unmanaged, with exact Publisher `os_bso_rs_support`, prefix `os`. No identity/tenant GUID, credential, token, organization URL, or Candidate PII is included in this report. Process token references/pins are cleared in `finally`.

## 4. Fresh Candidate Core Storage Reconciliation

Candidate, Call Log, History, frozen Choices, ownership, audit metadata, relationships, keys, and Solution inclusion passed fresh guarded checks before receipt writes and each API plan/apply/final-reconciliation stage.

- Previous/New Status bind to `os_sr_candstat`; repaired MetadataId hashes match retained successful Phase 3B.2 evidence.
- Call Log outcome remains bound to `os_sr_callout`.
- Candidate optimistic concurrency remains enabled.
- No existing Candidate/Call/History attribute, key, Choice, or table was altered.
- Only the approved new Candidate-to-receipt relationship was added.
- Final count-only aggregate reads: Candidate 0, Call Log 0, History 0, Operation Receipt 0. No business field values were retrieved for these checks.

## 5. Audit State

Candidate Core and receipt table audit metadata is enabled; organization auditing remains disabled. The receipt Candidate lookup audit flag is also GET-confirmed enabled after one targeted metadata update.

Retain **`AUDIT_ACTIVATION_PENDING`**. The owner explicitly allowed API/plugin metadata deployment before external activation. Runtime rejects business execution with `AUDIT_ACTIVATION_PENDING` while organization auditing is inactive.

## 6. Approved Business Operations

Exact endpoint: **`os_sr_cact` / Apply Candidate Action**.

Implemented actions: `CreateCandidate`, `UpdateCandidate`, `RecordCall`, `ProceedToScheduling`. The allowlist also recognizes `MarkRound1Scheduled`, `RecordPass`, `RecordFail`, and `RequestReschedule`, but rejects execution until the future trusted scheduler/result/cancellation evidence boundaries exist. No external provider is called.

## 7. Workflow Transition Contract

Canonical states: Need Call Candidate `100010000`, Candidate Answered `100010001`, Waiting Manual Scheduling `100010002`, Round 1 Scheduled `100010003`, Offer Extended `100010004`, Candidate Failed `100010005`.

Answered call advances Need Call to Answered; ProceedToScheduling advances Answered to Waiting. Future verified booking advances Waiting to Scheduled; future authorized Pass/Fail advances Scheduled to the corresponding terminal state. Reschedule returns Scheduled to Need Call only through the future cancellation boundary with mandatory reason/history. Skips, terminal rollbacks, legacy approval states, unknown actions, and invalid combinations are rejected.

Future-evidence transition tests validate the semantic matrix, not an API input that bypasses missing evidence. The deployed API has no untrusted evidence-override flag.

## 8. Record Call Contract

| Frozen outcome | Integer | Effects |
|---|---:|---|
| Answered | `100010000` | One Call Log + Candidate Answered + one History + receipt |
| No Answer | `100010001` | One Call Log + receipt; no Candidate update or History |
| Call Back Requested | `100010002` | One Call Log + receipt; no Candidate update or History |

Only Need Call Candidate is valid. The handler validates Candidate, expected status, CorrelationId, outcome, and UTC contact time; future timestamps are rejected. It derives Contacted By from the initiating caller. No option value is inferred from label ordering.

## 9. Candidate Transition Contract

Action allowlisting determines target state; the client cannot supply arbitrary previous/new status pairs. Current state is retrieved under caller permissions. Stale expected status is rejected. Candidate writes use `UpdateRequest` with `ConcurrencyBehavior.IfRowVersionMatches`; missing row version fails closed.

Profile replacement semantics: present fields replace; omitted fields preserve; explicit null clears only optional Phone/Position/Candidate Source. Name/email cannot be blank/null. Create requires Name/Email, assigns owner from the initiating caller, and leaves Candidate Number generation to Dataverse. No initial fabricated History is created.

## 10. Idempotency Contract

The owner explicitly approved receipt storage after the earlier report proved the non-transition update evidence gap. The extension is limited to [the receipt contract](PHASE_3C_OPERATION_RECEIPT_PLAN.json), not unrelated schema.

External CorrelationId remains a nonempty GUID. Infrastructure stores its lowercase canonical D-format **String(36)** under unique alternate key `os_sr_oprc_ak_corid`, avoiding unsupported GUID key types. Identity is API-wide across callers/actions/Candidates, as in the reviewed proposal.

Versioned length-delimited SHA-256 fingerprint includes initiating actor and all supplied validated inputs: correlation, action, target, expected status, replacement/call/reason fields. Input order is normalized; omitted/null/type boundaries are distinct. No raw contact, notes, reason, or request payload is stored in receipts.

Exact replay compares actor/action/fingerprint/version, rechecks current Candidate read access, and returns persisted original statuses/effect IDs with `DuplicateReplay`, even after later edits. Changed intent returns `CORRELATION_CONFLICT`; concurrent duplicate-key faults roll back the transaction rather than retry. Receipts are append-only, with no deletion/expiration authorized. Digests remain sensitive evidence, not anonymization; row access and retention governance still apply.

## 11. Transaction Model

The Action's synchronous main-operation plugin requires Stage 30, synchronous mode, `IsInTransaction`, top-level invocation, and UserId = InitiatingUserId. Candidate, applicable child records, and receipt share this transaction. SDK faults propagate through explicit stable plugin errors; no transaction fault is swallowed or followed by another business service call.

Answered effects either commit together or roll back. Status-only transitions write Candidate + History + receipt together. Non-answer calls write Call + receipt without a Candidate semantic write. Unique receipt insertion prevents duplicate committed effects on a correlation race.

Offline host rollback simulation exercises each failure boundary; SDK adapter tests exercise real request types with fake services. **Live Dataverse rollback/concurrency behavior has not been transaction-tested**, because API invocation/business rows are prohibited in this phase.

## 12. Actor / Execution Context

The service factory explicitly selects the initiating caller; different execution-user and nested contexts are rejected. All steps have no impersonating-user lookup. No SYSTEM, registration-owner, fixed account, or TA substitution.

Contacted By, History Actor, and record owner come from the caller. Receipt `createdby`/owner retain actor evidence. Direct Create/Update requires an exact mutation fingerprint in the synchronous parent API context. Other guarded mutation paths are rejected. Associate/Disassociate guards reject only project tables/relationships and no-op for unrelated associations.

## 13. Candidate Privilege Discovery

Fresh table metadata confirmed `prvCreateos_sr_cand`, `prvReados_sr_cand`, `prvWriteos_sr_cand`, plus Delete/Assign/Share/Append/AppendTo. Metadata supports Basic/Local/Deep/Global depths; that does not prove a given caller has them.

Required table/row permissions remain operation-specific: Candidate Create or Read/Write; child and receipt Read/Create; relevant Append/AppendTo and actor lookup access. No role/grant was added. Basic/User depth is the intended minimum for owned records; broader scope is not assumed.

## 14. ExecutePrivilegeName Decision

Deployed and reconciled: **`prvWriteos_sr_cand`**.

Rationale: supported existing generated Candidate mutation privilege; Read alone must not authorize a mutating endpoint. No fake/surrogate privilege was created. Creation still requires underlying Create; record updates and child/receipt operations use caller-context access checks enforced by Dataverse.

Limitations: the API privilege is not a substitute for row-level checks, underlying child/receipt privileges, or direct-write guards. A separately approved caller role and non-admin positive/negative tests remain required before business acceptance. Metadata deployment does not claim those grants/tests occurred.

## 15. Custom API Definitions

| Property | GET-reconciled value |
|---|---|
| UniqueName | `os_sr_cact` |
| Name / DisplayName | Apply Candidate Action |
| IsFunction | false |
| IsPrivate | true; discovery control, not an authorization boundary |
| BindingType | 0 / unbound |
| BoundEntityLogicalName | Not used |
| AllowedCustomProcessingStepType | 0 / None |
| WorkflowSdkStepEnabled | false |
| ExecutePrivilegeName | `prvWriteos_sr_cand` |
| Main-operation handler | `os_sr_cact.ApplyCandidateAction` |

Inputs (13): CandidateId Guid, ActionType String, ExpectedStatus Integer, CorrelationId Guid, CandidateName String, CandidateEmail String, CandidatePhone String, PositionId Guid, CandidateSourceId Guid, Reason String, CallOutcome Integer, ContactedAt DateTime, Notes String. Only common ActionType/CorrelationId are metadata-required; action-specific requiredness is enforced by the handler.

Outputs (5): ResultCode String, PreviousStatus Integer, CurrentStatus Integer, CallLogId Guid, StatusHistoryId Guid. Original output list is retained; no CandidateId output was silently added. Creation has no previous value; an unset Web API Integer output may return default 0, which is not a workflow status. Receipt previous status is null for creation.

## 16. Plug-in Architecture

- [Shared operation engine](../solutions/CandidateCore/Operation.cs): typed validation, canonical intent, replay, state decisions, atomic effect orchestration.
- [SDK adapter / guards](../solutions/CandidateCore/DataversePlugin.cs): caller-context service, audit/transaction guard, conditional update, receipt/effect persistence, stable PII-free errors/tracing.
- Two public plugin types in one signed assembly; no configuration secret or environment-specific ID.
- Fifty synchronous PreValidation rank-1 guards: 12 supported mutation hooks per protected table (48), plus two project-association guards.
- Per-table hooks: Create, Update, Delete, CreateMultiple, UpdateMultiple, DeleteMultiple, SetState, SetStateDynamicEntity, Assign, GrantAccess, ModifyAccess, RevokeAccess. Supported live message filters were discovered, not guessed. Upsert follows underlying Create/Update paths; no table-specific Upsert hook was exposed by live discovery.
- No UI, app, flow, scheduler, Outlook/Teams/email, or external provider integration.

## 17. Offline Test Results

| Suite | Assertions | Result |
|---|---:|---|
| Candidate Core design | 46 | PASS |
| Phase 3B.2 | 50 | PASS |
| Reference provisioning | 550 | PASS |
| Readiness | 11 | PASS |
| App composition | 329 | PASS |
| Receipt plan/payload/safety | 27 | PASS |
| Deployment contract/safety | 23 | PASS |
| Shared operation engine | 56 | PASS |
| Real SDK adapter/guard types with synthetic services | 53 | PASS |
| Total | **1,145** | PASS |

Covered: three outcomes, queue transition, future transition contracts and fail-closed execution, invalid/terminal/stale paths, reason/outcome/correlation/actor validation, exact replay, conflicting reuse, later-edit replay, no fabricated history, rollback simulation, concurrency rejection, audit gate, caller context, conditional SDK writes, tampered mutation rejection, and unrelated-association isolation.

PowerShell deployment tests are source/contract assertions, not live writes. The in-memory rollback test is not a live Dataverse transaction test. All test data is synthetic. See [test instructions](../tests/README.md).

## 18. Assembly Build / Fingerprint

Clean Release build: **0 warnings, 0 errors**. Assembly `os_sr_cact`, version `1.0.0.0`, .NET Framework 4.6.2, signed using a protected session-local strong-name key. `Microsoft.CrmSdk.CoreAssemblies` is pinned at 9.0.2.60; no unrelated dependency upgraded. The SDK assemblies are supplied by the sandbox.

Strong-name identity: `os_sr_cact, Version=1.0.0.0, Culture=neutral, PublicKeyToken=d73b02688ba7f9aa`. This public strong-name token is not an authentication credential.

**Deployed assembly SHA-256:** `f11d6db0db3a190806ef48daa46a3f3b6befbf7070f236bac5a44b6e40598f0f`.

Private signing material is not in the repository. Future compatible updates must preserve signing identity. No plugin NuGet package/dependent assembly was needed; this is direct signed assembly registration.

## 19. Pre-Deployment Live State

Fresh pre-deployment gates verified target, credential/WhoAmI pin, Solution/Publisher, unchanged Candidate Core, complete receipt with Active key, current hashes, and absence of exact assembly/type/API/guard names. The first local registration plan was superseded before any API/plugin write to add association protection. The final 72-write plan was pinned before dispatch.

## 20. Planned Write Counts / Fingerprints

Final API deployment-plan SHA-256: `0314c87e233a4328b368edd9fa6f349e3b89d765113267d52bfd3236da38e2a8`.

It records every generated registration identity, full body, and individual body fingerprint, plus assembly/core/receipt/API hashes and exact hook coverage. The private session files retain the plan and durable pre-dispatch journal; no assembly/API create was resent. All 72 entries reached `GET_RECONCILED`.

Receipt schema used five separately bounded writes: table create; primary-name property PUT; Candidate relationship create; lookup-audit PUT; alternate-key create. No deletion or recreation.

Observed receipt body hashes:

| Dispatch | SHA-256 |
|---|---|
| Original table POST | `db7e9b6f31c541a8a71d1914c25ca57b68fe1c7dbe4f8062dced4892f88f33e7` |
| Exact primary-name PUT | `05cc75550333c60cbdfdf5623ddffd62017cec23e6cc422590fc57428251b543` |
| Candidate relationship POST | `ddea14f3a458d540c9b55f674439a0ce0b694b1b3baac73a7580ac5e6186fe5b` |
| Lookup-audit PUT | `a7ec48255968cfa1224dd4a39f8b695ad33c3b0e9fc7f0aaf9b69e7abf88b907` |
| Canonical String key POST | `8391e699bd1331c9a81db9f9f49339b4609a75adfbfe0a6afbd2a8a64bf455f3` |

## 21. Plug-in Deployment

One assembly, two types, and 50 steps created once each, individually GET-reconciled; strong-name identity/version/content hash and calling-user step properties exact. Assembly root includes types. No separate main-operation processing step is invented: the API's PluginTypeId associates its main handler.

## 22. Custom API Deployment

One API, 13 request parameters, five responses created once each, individually GET-reconciled. Actual navigation property names were resolved from metadata before dispatch. No existing API was overwritten or duplicated.

## 23. API Metadata Reconciliation

Final GET-only reconciliation returned the current success classification. It rechecked all 72 records/associations, enabled calling-user guards, exact API/parameter inventory, no duplicate assembly/types/API/guard names, and Solution inclusion.

An initial final-membership verifier incorrectly assumed static Custom API component codes. Read-only diagnosis proved the API was already in the approved Solution with Include Subcomponents. Actual metadata codes are API `10036`, request `10037`, response `10038`. The verifier now resolves these from live ObjectTypeCode metadata. **No AddSolutionComponent or registration retry occurred.** Original plan's static membership hints were not transmitted payload properties; all pinned request bodies and assembly hashes remain unchanged.

## 24. Business-Data Non-Execution Proof

Deployment transports allow only metadata/registration paths, never business entity writes or business API invocation. Runtime handler was not called. Final aggregate counts across all four tables were 0; no Candidate/contact/history values were retrieved.

No claim is made about unrelated actors' activity. No live workflow, AutoNumber, end-to-end authorization, race, or transaction test ran. External audit and later explicit business-data test authorization are still required.

## 25. Request / Write Counts

Counts below cover this **17:29 receipt-authorized continuation**, excluding the earlier 74-GET Phase 3C preflight and the earlier attachment-only zero-request disposition.

| Recorded stage | Instrumented GET | POST | PUT |
|---|---:|---:|---:|
| First receipt preflight: local helper-state failure | 48 | 0 | 0 |
| Second receipt preflight: manifest-property correction needed | 50 | 0 | 0 |
| Successful receipt preflight | 72 | 0 | 0 |
| Receipt table dispatch/readback stop | 74 | 1 | 0 |
| Primary-name diagnostic | 2 | 0 | 0 |
| Primary PUT + relationship POST/readback stop | 85 | 1 | 1 |
| Lookup diagnostic | 2 | 0 | 0 |
| Lookup audit PUT + key POST/Pending stop | 87 | 1 | 1 |
| Pending key diagnostic | 2 | 0 | 0 |
| Complete receipt reconciliation, key Active | 77 | 0 | 0 |
| First API registration plan | 100 | 0 | 0 |
| Final API registration plan | 100 | 0 | 0 |
| API deployment and initial membership-verifier stop | 326 | 72 | 0 |
| Membership diagnosis | 19 | 0 | 0 |
| Actual component-code discovery | 21 | 0 | 0 |
| Corrected full final API reconciliation | 335 | 0 | 0 |
| Final count-only closeout | 25 | 0 | 0 |
| **Total instrumented Dataverse Web API** | **1,425** | **75** | **2** |

| Mutation category | Dispatched |
|---|---:|
| Receipt table create | 1 |
| Receipt primary-name metadata update | 1 |
| New Candidate-to-receipt relationship | 1 |
| Receipt lookup audit metadata update | 1 |
| Receipt alternate key create | 1 |
| Plugin assembly | 1 |
| Plugin types / steps | 2 / 50 |
| Custom API | 1 |
| API parameters / responses | 13 / 5 |
| Existing Candidate/Call/History table/column/key changes | **0** |
| Choice definition writes | **0** |
| Business-data writes / API invocations | **0 / 0** |
| App / role / access / organization-audit-setting writes | **0** |
| PublishXml / PublishAllXml | **0 / 0** |
| DELETE / PATCH / AddSolutionComponent | **0 / 0 / 0** |
| Automatic retries | **0** |

The new relationship is the explicit receipt-only exception, not a modification to Candidate attributes. Total controlled metadata/registration mutations: **77**.

One supported PAC Solution export and one local unpack also completed. **PAC internal reads are not instrumented**, so 1,425 is not presented as the total network request count across PAC and Web API. No solution import/publication was invoked. PAC target/auth informational calls are not counted as instrumented Web API GETs.

## 26. No-Retry Proof

Each schema/registration write was reserved durably before network dispatch. Journals record its fingerprint, acknowledgment, and reconciliation. No create/update was dispatched twice. Later read-only reconciliation after local verifier fixes or asynchronous indexing is not a write retry.

Receipt chronology: table POST returned 204 but primary-name defaults were 850/optional; a new bounded PUT set 36/required. Relationship POST returned 204 but lookup audit remained false; a new bounded PUT enabled it. Key POST returned 204; state was Pending after the initial wait, so processing stopped. A later GET showed Active. No key create/retry was performed.

## 27. Regression Results

All nine offline suites passed, **1,145 assertions**. Release build passed with zero warnings/errors. Final local checks passed: PowerShell parser for 15 files; 209 relative file links; all 32 report sections in sequence; privacy literal scan across 24 changed/new files; unchanged core manifest and exact receipt/API/deployed-assembly hashes; tracked/new-file whitespace and `git diff --check`. The signed SDK harness rebuild reproduced the deployed assembly hash. Live business acceptance is deliberately not claimed.

Supported metadata export/unpack was retained in private session storage, not copied wholesale into source: it includes the wider existing Solution beyond this surgical change. Snapshot ZIP SHA-256: `1884ae34b2096631003eba6f7effefca44cd3e879f33a699ba16e13bc70193f0`. No hand-authored Solution XML or fake export is presented as generated source.

## 28. Files Changed

- [Receipt contract](PHASE_3C_OPERATION_RECEIPT_PLAN.json), [API contract](PHASE_3C_API_CONTRACT.json), this report, [Current State](CURRENT_STATE.md), [design](PHASE_3A_CANDIDATE_CORE_DESIGN.md), [Data Model](DATA_MODEL.md), [Product Decisions](PRODUCT_DECISIONS.md), [Project Context](PROJECT_CONTEXT.md), [Implementation Plan](IMPLEMENTATION_PLAN.md).
- [Receipt runner](../scripts/Provision-BsoRsOperationReceipt.ps1), [deployment runner](../scripts/Deploy-BsoRsCandidateOperations.ps1), [script instructions](../scripts/README.md).
- [Plugin source/build instructions](../solutions/CandidateCore/README.md), [Solution source guidance](../solutions/README.md).
- [Operation tests](../tests/CandidateCore/Program.cs), [SDK tests](../tests/CandidateCoreSdk/Program.cs), [receipt tests](../tests/Phase3COperationReceipt.Tests.ps1), [deployment tests](../tests/Phase3CDeployment.Tests.ps1), [test instructions](../tests/README.md).

The current core manifest and existing provisioning/app implementations are unchanged. Generated build outputs/private keys/export snapshots are not added to source.

## 29. Final Classification

**`CANDIDATE_CORE_API_DEPLOYED_AUDIT_ACTIVATION_PENDING`**

The earlier `PRE_DEPLOYMENT_GATE_BLOCKED` and intermediate metadata/readback stops are historical and superseded by explicit receipt approval and successful final reconciliation. This classification is metadata-scope acceptance only.

## 30. Audit Follow-up

IT/Compliance must resolve organization audit activation, retention/access/capacity, and business evidence governance. No audit setting or receipt retention purge is authorized here. Do not enable production use or create test rows merely because deployment succeeded.

## 31. Exact Recommended Next Task

After audit governance and an approved least-privilege caller role are ready, obtain separately bounded synthetic end-to-end test authorization. Test real Dataverse transaction rollback, concurrent duplicate/conflicting submissions, lost-update rejection, actor/ownership, direct write guards including bulk/association paths, and non-admin positive/negative access.

Any necessary corrective code/metadata deployment must use fresh guarded reconciliation and a new precomputed bounded plan. UI composition, scheduler/result/cancellation evidence, app exposure, integrations, publication, access grants, and business rows remain separately authorized work. Do not rerun consumed Apply modes.

## 32. AI HANDOVER

Storage and API/plugin metadata are provisioned and exact. Operation Receipt table `os_sr_oprc` uses canonical String key and minimal immutable evidence; all four business tables are empty. `os_sr_cact` is private/unbound, caller-context, gated by `prvWriteos_sr_cand`, with audit and transaction checks plus server write guards.

The Phase 3B.2 History repairs remain correct; do not repeat any table/column replacement or in-place Choice rebind. Recompute current source/contract/assembly hashes on resume. Retained session journals and the supported export/unpack are evidence, not authorization to resend writes.

No grant, app/UI change, external integration, publication, business invocation, commit, or push occurred. Production runtime/effective-user acceptance is pending separate governance/test work, not silently inferred from offline suites or metadata deployment.
