# Phase 3C - Candidate Core Custom API + Plug-in Report

Date: 24 October 2026. Source: owner-supplied Phase 3C instructions, current repository contract, retained earlier Phase 3C read-only evidence, and the local checks reported below.

## 1. Executive Summary

**`PRE_DEPLOYMENT_GATE_BLOCKED`**. Candidate Core API/plugin implementation and deployment are not complete. The current contract requires durable replay/conflict detection for non-transition `UpdateCandidate`, but the current three-table manifest does not retain its accepted operation intent or original result. The attached instructions explicitly require Candidate schema writes to remain zero and authorize only API/plugin deployment components, not a new operation-evidence table.

Do not deploy an incomplete endpoint, silently weaken replay guarantees, or reinterpret the repeated completion reminders as schema approval. The additive operation-receipt design in [Section 27 of the Candidate Core design](PHASE_3A_CANDIDATE_CORE_DESIGN.md#27-phase-3c-preflight-and-operation-evidence-dependency) remains a proposal. No new owner approval of that extension was supplied. The prior successful storage result is unaffected.

All five existing offline suites passed: **986 assertions**. No Phase 3C assembly, API, parameter, business record, or schema component was created. This report is a blocked handover, not a successful deployment report.

## 2. Repository / Manifest Baseline

| Item | Refreshed local evidence |
|---|---|
| Repository | BSO-RS-Support, not legacy ATSugg |
| Root | Owner's opened BSO-RS-Support workspace; personal home-path segments omitted |
| Branch | `main` |
| HEAD | `3e26043c1e1b5f60a698ec1adab6e1d810726bee` |
| HEAD timestamp | `2026-10-24T17:19:55+07:00` |
| HEAD subject | `docs: Update Phase 3A and 3C documentation to reflect current status and dependencies` |
| Local `origin/main` reference | Same commit; no fetch or remote freshness claim |
| Worktree before this report | Clean; previously changed documentation is preserved in the baseline commit |
| Manifest | [Current Candidate Core manifest](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json) |
| Computed SHA-256 | `63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915` |
| Existing solution source | [Solutions directory](../solutions/README.md) contains its README only; no plugin project present |

No reset, restore, stash, pull, rebase, branch switch, commit, or push was performed. The existing baseline commit was observed, not created by this report task. Historical manifest fingerprints were not used as current guards. The manifest's historical provisioning ledger is not the current live classification.

## 3. Environment / Identity Guard

The retained earlier Phase 3C preflight verified VN LMV IT using the active PAC target, the actual Az.Accounts `Get-AzAccessToken` credential path, WhoAmI, and a process-scoped expected-user pin, plus exact Solution `os_sr_bso_rs_support` and Publisher `os_bso_rs_support` with prefix `os`.

**This attachment follow-up made no tenant request or authentication call.** Those live guards were not rerun after the new attachment: the current local contract dependency blocks deployment before a live pre-deployment gate is meaningful. No interactive login or environment change occurred. No token, user identity, tenant identifier, or organization URL is included here.

## 4. Fresh Candidate Core Storage Reconciliation

Retained same-session preflight evidence: Candidate, Call Log, and Status History reconciled exactly to the current manifest, including ownership, audit metadata, relationships, keys, and Solution inclusion. History contained 0 rows. Both repaired attribute MetadataId hashes matched the retained successful replacement journal.

- History Previous Status and New Status: `os_sr_candstat`, not `os_sr_callout`.
- Call Log outcome: `os_sr_callout`.
- Candidate optimistic concurrency: enabled.

This is the earlier 74-GET preflight, **not a newly executed live reconciliation for the attachment**. No storage drift is established, and this report does not classify uninspected later live state as exact or absent. Storage must be freshly reconciled again before any eventual write. No storage repair was attempted.

## 5. Audit State

Last verified: Candidate Core table audit metadata enabled; organization auditing disabled. Retain **`AUDIT_ACTIVATION_PENDING`** as an external governance prerequisite.

Per owner authorization, organization audit activation does not block API/plugin metadata deployment. It does block authorized Candidate business-data use under current project governance. No audit setting changed. This is not the reason deployment stopped.

## 6. Approved Business Operations

Exact current endpoint: **`os_sr_cact`**, display name **Apply Candidate Action**. No additional API name is invented.

Current action allowlist: `CreateCandidate`, `UpdateCandidate`, `RecordCall`, `ProceedToScheduling`, `MarkRound1Scheduled`, `RecordPass`, `RecordFail`, and `RequestReschedule`. Future booking/result/cancellation dependencies remain enforced; inclusion in the transition matrix is not permission to invent their evidence or enable them prematurely.

## 7. Workflow Transition Contract

| Action | From | To / boundary |
|---|---|---|
| `CreateCandidate` | No Candidate | Need Call Candidate |
| `UpdateCandidate` | Existing Candidate | Profile replacement only; no status change |
| `RecordCall` / Answered | Need Call Candidate | Candidate Answered |
| `RecordCall` / other approved outcomes | Need Call Candidate | Unchanged |
| `ProceedToScheduling` | Candidate Answered | Waiting Manual Scheduling |
| `MarkRound1Scheduled` | Waiting Manual Scheduling | Round 1 Scheduled; future verified booking evidence required |
| `RecordPass` | Round 1 Scheduled | Offer Extended; future authorized result evidence required |
| `RecordFail` | Round 1 Scheduled | Candidate Failed; future authorized result evidence required |
| `RequestReschedule` | Round 1 Scheduled | Need Call Candidate; reason required; disabled until cancellation-attempt boundary exists |

Terminal rollback, skipped stages, legacy TA approval stages, stale status, unknown actions, and missing required evidence must fail closed. None of these paths has been executed by a deployed Phase 3C handler.

## 8. Record Call Contract

Frozen manifest mapping, previously live-reconciled; not inferred from label order:

| Outcome | Value | Atomic effects |
|---|---|---|
| Answered | `100010000` | One Call Log + Candidate transition + one History |
| No Answer | `100010001` | One Call Log only; no transition or History |
| Call Back Requested | `100010002` | One Call Log only; no transition or History |

All three apply only from Need Call Candidate. Inputs must validate Candidate, expected state, correlation GUID, outcome, and contact time. Actor comes from the authenticated initiating user, not client input.

## 9. Candidate Transition Contract

Use the current six Candidate status integers: Need Call Candidate `100010000`, Candidate Answered `100010001`, Waiting Manual Scheduling `100010002`, Round 1 Scheduled `100010003`, Offer Extended `100010004`, Candidate Failed `100010005`.

Server derives the target state from allowlisted action/evidence, retrieves authoritative Candidate state, and compares expected status and Dataverse RowVersion. No client-supplied arbitrary previous/new pair is trusted. Reschedule requires reason and the later cancellation boundary. No provider integration or scheduling evidence is fabricated.

## 10. Idempotency Contract

Every state-changing operation requires a caller-generated GUID CorrelationId. Identical replay must return original effect identifiers/outcome without new rows; changed action/payload reuse must fail deterministically.

**Proven gap:** Candidate has only creation CorrelationId; Call/History keys identify their own effects. `UpdateCandidate` must create neither log nor history. Two earlier update payloads followed by the same later edit can leave identical current Candidate/Call/History state, but require different replay decisions. Current fields cannot reconstruct the accepted intent or result; RowVersion does not supply missing operation history. Comparing current replacement values is insufficient.

Creation replay after profile edits also needs preservation of original intent. Audit logs, in-memory caches, mutable notes, fabricated history, and overwriting creation correlation are not approved receipt stores.

The proposal in [design Section 27](PHASE_3A_CANDIDATE_CORE_DESIGN.md#27-phase-3c-preflight-and-operation-evidence-dependency) requires owner review of operation-identity scope, immutable evidence, payload fingerprint privacy/key management, retained results, retention/replay guarantees, and access. The current manifest and zero-schema-write boundary were preserved.

## 11. Transaction Model

Approved requirement: synchronous Custom API main-operation plugin; Candidate and applicable child effects commit together in the Dataverse transaction. Stale-row or duplicate-key faults must roll back all effects; no swallowed transaction faults, external distributed transaction, or internal retry.

No handler was built or registered. `IsInTransaction` behavior, transaction rollback, and replay races have **not** been validated for an actual Phase 3C assembly. A future implementation must verify supported main-operation behavior and fail closed if invoked outside its required transaction.

## 12. Actor / Execution Context

Caller context is the intended non-elevated approach; actual initiating actor must populate Contacted By/Actor and creation ownership. Never accept actor/owner IDs from untrusted input or silently substitute registration owner, TA, SYSTEM, or a fixed connection identity.

Caller-context services require the relevant table/row/append permissions. Direct writes must be rejected through reviewed server guards; hiding fields is insufficient. No explicit execution user, service identity, impersonation, grant, or guard step was introduced.

## 13. Candidate Privilege Discovery

Retained live metadata contained:

- `prvCreateos_sr_cand`
- `prvReados_sr_cand`
- `prvWriteos_sr_cand`
- `prvDeleteos_sr_cand`
- `prvAssignos_sr_cand`
- `prvShareos_sr_cand`
- `prvAppendos_sr_cand`
- `prvAppendToos_sr_cand`

Returned depth support included Basic/Local/Deep/Global. That is platform support, not an actual role grant or effective caller depth.

## 14. ExecutePrivilegeName Decision

**Not finalized/deployed.** `prvWriteos_sr_cand` remains a candidate existing mutating-endpoint gate, not a fake custom privilege. Basic/User depth is the proposed minimum for owned records; no broader access is assumed. Creation still needs Create and updates require current row access. Read alone cannot authorize mutation.

Limitations: ExecutePrivilegeName is an endpoint privilege check, not a complete action-specific/row-level or child-write authorization model. Shared access, ownership changes, Append/AppendTo, child Create, and direct CRUD protection require an explicit effective-access design. No non-admin caller acceptance test was authorized/executed. Do not interpret discovered privilege names as production least-privilege validation.

## 15. Custom API Definitions

| Property | Current contract / disposition |
|---|---|
| UniqueName | `os_sr_cact` |
| Name / DisplayName | Apply Candidate Action; no record created |
| IsFunction | `false` (Action) |
| BindingType | Unbound |
| BoundEntityLogicalName | Not applicable |
| IsPrivate | Not frozen in manifest; private is a proposal, not an authorization boundary |
| AllowedCustomProcessingStepType | Not frozen; `None` is a proposed closed-handler setting, not deployed |
| ExecutePrivilegeName | Not finalized; see Section 14 |
| PluginTypeId / handler identity | Not assigned or registered |

Approved inputs: CandidateId Guid, ActionType String, ExpectedStatus Integer, CorrelationId Guid, CandidateName String, CandidateEmail String, CandidatePhone String, PositionId Guid, CandidateSourceId Guid, Reason String, CallOutcome Integer, ContactedAt DateTime, Notes String. Action-specific requiredness is defined in [the manifest](PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json); CandidateId is omitted only for creation.

Approved outputs: ResultCode, PreviousStatus, CurrentStatus, CallLogId, StatusHistoryId. Exact metadata types for every response, optional/null behavior, and update field-replacement semantics must be frozen before payload generation. CandidateId creation output is a proposal in design Section 27, not silently added. No request/response metadata payload has been generated or dispatched.

## 16. Plug-in Architecture

No implementation project exists. Intended architecture remains: strict typed validation, authoritative caller/record checks, deterministic transition decision, durable replay/conflict evaluation, atomic caller-context mutations, and PII-free error codes/tracing. Separate table-message guards would protect API-only Candidate writes and immutable child evidence, with reviewed trusted-parent validation and coverage of bulk/alternate paths.

Exact guard messages, registered types/steps, assembly identity/version, and SDK package versions are not yet frozen. No unsupported SDK package approval, elevated identity, new schema, or partial production handler is invented.

## 17. Offline Test Results

Executed from repository root using PowerShell:

| Suite | Assertions | Result |
|---|---:|---|
| [Candidate Core design](../tests/Phase3ACandidateCoreDesign.Tests.ps1) | 46 | PASS |
| [Phase 3B.2 child provisioning](../tests/Phase3B2CandidateChildProvisioning.Tests.ps1) | 50 | PASS |
| [Reference provisioning](../tests/ReferenceTableProvisioning.Tests.ps1) | 550 | PASS |
| [Readiness](../tests/ReadinessChecks.Tests.ps1) | 11 | PASS |
| [App composition](../tests/ModelDrivenAppComposition.Tests.ps1) | 329 | PASS |
| Total | **986** | PASS |

These scripts use synthetic fixtures/mocked transport and report no authentication/network/business-data calls. Existing design tests check transition/call/replay contract declarations, not actual handler execution.

New handler-path tests for valid/invalid transitions, RecordCall, replay/conflicting reuse, stale-state races, actors, privilege enforcement, API metadata, and rollback: **NOT IMPLEMENTED / NOT RUN** because the contract is blocked and no handler exists. The earlier synthetic indistinguishable-state check is dependency evidence, not a runtime idempotency test.

## 18. Assembly Build / Fingerprint

**NOT BUILT.** No assembly/package or SHA-256 exists. No restore/install/signing/package operation ran. Earlier local inspection found .NET SDKs 8.0.206 and 10.0.402; their availability is not proof of a supported Dataverse build. No build/test gate is represented as passed.

## 19. Pre-Deployment Live State

**NOT EXECUTED for this attachment follow-up.** The contract dependency prevents proceeding to first-write guards. Retained earlier exact-name API query found `os_sr_cact` absent. Narrow assembly-name discovery found no `BsoRs*` / `BSO*` matches; it did not prove exhaustive assembly/type/step absence.

Fresh identity, target, manifest/storage, complete registration discovery, Solution/Publisher, built assembly hash, and existing API/parameter metadata must be reverified immediately before any later authorized deployment.

## 20. Planned Write Counts / Fingerprints

Current executable plan: **zero writes**, because a deployment plan cannot be precomputed for an unfrozen contract. No assembly/API payload or payload fingerprint exists. This is not a fictitious successful zero-write deployment. Future deployment requires exact per-component payloads, identities, counts, deterministic fingerprints, and uncertainty/journal boundaries before dispatch.

## 21. Plug-in Deployment

Not attempted. No assembly, type, step, handler association, or Solution-membership mutation.

## 22. Custom API Deployment

Not attempted. No API, request parameter, response property, or Solution-membership mutation.

## 23. API Metadata Reconciliation

Post-deployment reconciliation not applicable: no deployment. No claim of exact handler, privacy flag, privilege, parameters, response types, binding, or membership. Future readback must verify all these plus no duplicates before declaring API deployed.

## 24. Business-Data Non-Execution Proof

This follow-up invoked only local file/Git inspection and the five offline test scripts; no Dataverse transport or API invocation was called. No Candidate/Call/History record was created, retrieved for field contents, updated, or deleted. Retained earlier History inspection was count-only. This is an agent-operation record, not an assertion about unrelated users' tenant activity.

## 25. Request / Write Counts

| Category | Attachment follow-up | Retained earlier Phase 3C preflight |
|---|---:|---:|
| Dataverse GET | **0** | **74** |
| Plug-in assembly writes | 0 | 0 |
| Plug-in type/step writes | 0 | 0 |
| Custom API writes | 0 | 0 |
| API parameter writes | 0 | 0 |
| API response writes | 0 | 0 |
| Solution membership writes | 0 | 0 |
| Candidate schema writes | **0** | **0** |
| Other schema / Choice writes | 0 | 0 |
| Business-data writes | **0** | **0** |
| App writes | **0** | **0** |
| Security / audit-setting writes | 0 | 0 |
| PublishXml / PublishAllXml | 0 / 0 | 0 / 0 |
| Automatic retries | **0** | **0** |

The earlier 74 GETs are not counted twice or presented as fresh follow-up requests. Local baseline Git/file operations and local tests are not Dataverse GETs.

## 26. No-Retry Proof

No tenant request was dispatched by this follow-up, so no request was retried. The retained guarded preflight reported zero automatic retries. No ambiguous/failing write was resent. Existing destructive replacement and ineffective in-place-rebind operations were not invoked.

## 27. Regression Results

- All five current offline suites: PASS (Section 17).
- Baseline `git diff --check`: PASS.
- Final validation: PASS for PowerShell parser (11 script/test files), added-content privacy patterns (including this new untracked report), relative file-link targets in both changed documents, unchanged manifest hash, all 32 required report sections, tracked `git diff --check`, and new-report `git diff --no-index --check`.
- Plug-in build/tests and live operation acceptance: NOT RUN / blocked, not substituted with manifest tests.

## 28. Files Changed

- This [Phase 3C report](PHASE_3C_CANDIDATE_CORE_API_PLUGIN_REPORT.md).
- [Current State](CURRENT_STATE.md): link to this disposition and preserve distinction between current follow-up and retained live evidence.

No manifest, plugin source, solution artifact, environment configuration, app, or security file changed.

## 29. Final Classification

**`PRE_DEPLOYMENT_GATE_BLOCKED`**

Reason: required durable operation evidence is not available within the current approved schema/contract; the explicit zero-schema-write boundary prevents adding it without owner review. This is not a claim of authentication failure, storage drift, or Dataverse rejection, and not an API deployment success.

## 30. Audit Follow-up

IT/Compliance must approve organization audit activation, retention, access, and capacity before authorized business data and live transaction testing. Audit activation is external and does not replace resolution of the operation-evidence dependency or prevent API metadata deployment once the actual contract gates pass.

## 31. Exact Recommended Next Task

Owner review of [design Section 27](PHASE_3A_CANDIDATE_CORE_DESIGN.md#27-phase-3c-preflight-and-operation-evidence-dependency): authorize a minimal immutable operation-receipt extension under a separately bounded schema plan, or provide an approved durable alternative satisfying the unchanged replay contract. Freeze update replacement semantics, replay scope/privacy/retention, response definitions, and caller/direct-write security contract. Do not silently drop `UpdateCandidate`, use fabricated business history, or deploy success-shaped replay handling.

After that decision: implement and test the complete handler/guards locally, freeze the exact registration and payload plan, repeat fresh target/storage/API discovery guards, and deploy with zero retries and immediate GET reconciliation. No business invocation until separately authorized.

## 32. AI HANDOVER

- Storage last verified successful: `CANDIDATE_CORE_STORAGE_PROVISIONED_AUDIT_ACTIVATION_PENDING`; no further column replacement is needed.
- Manifest current SHA is in Section 2; recompute it on resume rather than copying historical guards.
- Phase 3C endpoint name is `os_sr_cact`; implementation/deployment remain absent from this work, not complete.
- The dependency is durable update-operation evidence, not organization audit activation or a proven transport failure.
- Retained live preflight was 74 GET / 0 writes; this follow-up was 0 GET / 0 writes.
- Existing five offline suites passed 986 assertions; no actual handler, concurrency/transaction acceptance, assembly build, or effective non-admin security test ran.
- No authorization exists here to create receipt storage, elevate execution identity, grant roles, change the app, publish, commit, or push.
- Do not repeat unavailable owner-review forms or declare completion based on an automated reminder. Resume implementation only after the material contract dependency is resolved.
