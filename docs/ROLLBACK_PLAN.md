# BSO-RS-Support Rollback Plan

**Status:** `ROLLBACK_PLAN_OFFLINE_READY`; the owner explicitly approved use of the existing LMV BI DEV pre-deployment checkpoint/recovery procedure for the bounded BSO-RS-Support Test rehearsal (`TEST_RECOVERY_PROCEDURE_APPROVED_FOR_BOUNDED_REHEARSAL`). This does not establish a safe bootstrap cleanup path or authorize routine whole-environment restore. No bootstrap import has occurred.

## Record Call 1.0.11 rollback

**Status (2026-11-18):** `PACKAGE_AND_CONSOLE_BYTES_VERIFIED_ROLLBACK_NOT_EXECUTED`. The [1.0.11 manifest](CANDIDATE_CORE_RECORD_CALL_1.0.11_RELEASE_MANIFEST.json) pins the protected 1.0.10 package: SHA-256 `fa0716a401f887b28bc2c7b1fb71f5264ece4490c084fb99697a0063c9263404`, embedded assembly `569e24423aa1e3352ef227c59fd1802ca78cb9cd3d509b94384f6572e4d5832f`. The fresh external Console journal retains the exact prior HTML/JavaScript bytes; decoded current/published rollback payloads were verified against HTML `377d9996c2518d2c5b45b307cf44c2ed21362e1457c128a09c38fdd7ab2e95c3` and JavaScript `b6a87078ca7bb840e80060b86e6891660bb98b44ad013d75c4516cc01daf9803`.

1. Stop submissions and reconcile uncertain Call/transition outcomes; never record another Call merely to repair a scheduling transition. Obtain a component-scoped recovery instruction and fresh baseline/journal.
2. Restore only the captured 1.0.10 HTML/JavaScript pair with fresh individual-row ETags and scoped two-resource `PublishXml`; verify current/published/served hashes.
3. If backend rollback is required, restore the pinned 1.0.10 package through the guarded existing-package updater. Its previous NORMAL call routing rejects unscoped calls again; it does not introduce a weaker callable write boundary. NORMAL Create remains protected.
4. Leave the unchanged 25/11 API contract, existing enabled exact-org configuration, environment/policy resources, roles, Candidate/Call/history/receipt data and consumed journals intact. There is no metadata delta to remove. An authorization incident needs separately authorized exact-org gate-disable containment, not a role or global-guard change.

The exported 1.0.11 solution is reconciliation evidence, not the rollback package. No rollback or Candidate mutation was executed.

## Candidate Core NORMAL Create 1.0.9 rollback

**Status:** `SERVER_GATE_DISABLE_READY_UI_RESTORE_NOT_REHEARSED`. Candidate Core 1.0.9.0 was deployed with NORMAL Create enabled; the subsequent 1.0.10 deployment preserves that gate and its authorization boundary. The external integrated bundle contains the protected 1.0.9 assembly package, hash-pinned prior Console payloads, target-bound configuration, and durable journals. The [1.0.9 release manifest](CANDIDATE_CORE_NORMAL_CREATE_1.0.9_RELEASE_MANIFEST.json) records sanitized evidence. The full solution export is source reconciliation only, not the rollback artifact.

The immediate safe rollback is to run the [deployer](../scripts/Deploy-BsoRsNormalCreateRelease.ps1) in `Deactivate` mode: conditionally set the exact-org `os_sr_ncrcfg` value to `enabled=false` with a fresh row ETag, then read back the disabled value. This alone blocks NORMAL Candidate mutations server-side while preserving the protected 1.0.9 handler, both additive API outputs, and SingleUserDev. A subsequent UI restoration is optional for server-side write containment. The existing `Rollback` mode targets the older 1.0.8 Console pair; it is not the exact four-resource post-1.0.9 NORMAL-mode UI restoration and must not be used as if it were.

The pre-NORMAL 1.0.9 Console payloads are hash-pinned in the external bundle and NORMAL-mode release record. Restoring all four resources would require a separate exact-resource change after the gate is disabled, with fresh row ETags and one scoped WebResource-only `PublishXml`; that full UI restoration has not been automated or rehearsed. Do not claim it has occurred.

Assembly recovery uses the included SHA-pinned **protected 1.0.9** package and `RecoverPackage`, with its separate one-shot journal against the same package/handler. The consumed deployment journal is never reused. An unprotected 1.0.8 downgrade is prohibited: it ignores `os_sr_ncrcfg`. Restricting the shared API privilege instead would disrupt Read-only SingleUserDev callers, so that prior proposal is superseded for this release. No weaker callable write boundary, role/team change or global guard is introduced.

The server-side disable path and protected 1.0.9 assembly recovery mode are prepared; neither rollback nor owner functional acceptance is claimed. Do not reset journals, automatically recover ambiguous writes, delete metadata or downgrade the assembly.

## Candidate pagination and Answered-to-scheduling 1.0.10 rollback

**Status (2026-11-18):** `PACKAGE_AND_CONSOLE_BYTES_VERIFIED_ROLLBACK_NOT_EXECUTED`. The deployed package and Console hashes are recorded in [Current State](CURRENT_STATE.md#candidate-pagination-and-answered-to-scheduling-1010-deployed-2026-11-18). The immutable [1.0.10 release manifest](CANDIDATE_CORE_PAGINATION_1.0.10_RELEASE_MANIFEST.json) pins the protected 1.0.9 package: SHA-256 `5b08bcfde39207d5069ce9c55ee4e1794622d69e7d0f148277f7b8f04a89802b`, embedded DLL `ea4a3cdcc6f17aff48441827eee7923dcf63df935ba55e56a02c5a84be4729bb`. The external deployment journal retains both prior Console payloads. The post-deployment solution export is reconciliation evidence, not the rollback artifact.

1. Stop submissions and reconcile the exact current package/API/WebResource identities and versions. Obtain an explicit component-scoped recovery instruction; do not reuse the completed release's apply plan or journals.
2. Restore only the prior Console HTML/JavaScript pair, using fresh individual-row ETags and scoped two-resource `PublishXml`. Prior target HTML SHA-256 is `e3756600154be5e8a138eb120c936af60299f2e557c5fd7bf087aebabcbb778b`; prior JavaScript SHA-256 is `d926e4ddc15ff33524b6cb33582d0bad527294b17eee6a58d8c27015ca9684e8`. Leave the environment and policy resources unchanged and verify current/published/served hashes.
3. If backend rollback is required, use the protected, hash-verified 1.0.9 package against the existing package/handler with a fresh rollback-specific baseline and one-shot journal. Verify assembly 1.0.9.0, handler binding, unchanged security and exact-org NORMAL gate. Never downgrade to unprotected 1.0.8.
4. Leave the five compatible additive API definitions installed while restoring the previous Console/backend; do not delete metadata during uncertain recovery. The optional inputs and unused response properties do not weaken the existing execute/Create authorization.
5. Preserve Candidate data, operation correlation/history, SingleUserDev scope and all consumed journals. A UI-only rollback does not require changing the NORMAL gate. An authorization incident instead uses the separately authorized exact-org gate-disable containment described above before any further recovery.

Artifact validation and preserved bytes do not prove a rehearsed rollback; no rollback or business mutation was executed.

## Preconditions

Before any Test or Production release, record the approved target, recovery window, restore point, expected data impact, and exact rollback authority. For the bounded Test rehearsal, the owner authorization covers BSO-RS-Support recovery using the existing checkpoint and the current deployment identity's existing privileges. Retain the reviewed managed Solution, package and web-resource hashes, dependency inventory, configuration policy, and a protected deployment journal outside the repository. Validate that any component-scoped recovery method is supported before use.

Do not proceed if the checkpoint is no longer valid, the rollback package or configuration is unverified, or external email/calendar/SharePoint effects cannot be reconciled. The current bootstrap is stopped because no safe BSO-only teardown is established.

Use component-scoped recovery first. Do not use whole-environment restore as routine cleanup. It is permitted only after a material failed BSO-RS-Support rehearsal, while the existing checkpoint is valid, and when impact to unrelated LMV BI DEV resources is explicitly proven acceptable under the existing recovery contract. A managed or unmanaged Solution delete is not presumed to remove all component customizations; specifically, deleting an unmanaged Solution removes its container but leaves customizations in the Default Solution.

The `rollbackPlan.decisionTree` in [ROLLBACK_MANIFEST.json](ROLLBACK_MANIFEST.json) is the authoritative predicate list. Before import, require a verified pre-import backup and baseline; exact prior approved managed Solution identity/hash; prior existing Candidate Core package identity/hash; Candidate Console resource and configuration hashes; approved configuration restoration procedure; current Custom API/package/handler topology; preserved Candidate Core-only protected write path and five direct-write denials; and an approved synthetic post-rollback smoke plus read-only reconciliation. The evidence fields are deliberately null until supplied and verified for the target.

## Stop and preserve evidence

1. Stop further UI submissions, imports, package updates, and retries.
2. Record the safe stage, sanitized platform code, artifact hash, target label, and dispatch journal location. Do not copy tokens, raw fault text, user IDs, environment IDs, candidate PII, CVs, or connector URLs into the report.
3. Perform read-only reconciliation of deployed component identity/version, package/handler topology, app navigation, configuration resource hashes, and affected synthetic test rows.
4. Do not repeat uncertain or non-idempotent operations. Preserve the journal and obtain explicit owner direction before any recovery write.

## Component-specific recovery

### Candidate Console resources

- Restore only the exact previously reconciled `candidate-console.html`, JavaScript, policy, and configuration resources, with their corresponding prior cache-bust hashes.
- Use the scoped Candidate Console refresh workflow for exact resources and `srapp`; reconcile each published resource and verify sitemap semantics remain unchanged.
- Never use `PublishAllXml`. Do not deploy the checked-in `UNCONFIGURED` template as a substitute for a known-good target configuration unless the approved response is to deliberately block Candidate Management.

### Managed Solution

- Use only the prior reviewed managed package and the approved environment recovery/import procedure. Reconcile Solution identity, version, components, dependencies, app state, and data impact after recovery.
- A managed Solution rollback is not assumed to undo data changes or external side effects. Do not delete business records to simulate rollback.
- The full Solution export and a tested prior managed artifact are not currently present in this workspace; this recovery path is **not ready**. The pre-rehearsal target baseline is empty for BSO-RS-Support, so cleanup must restore that exact state without affecting other resources.

### Candidate Core package

- Any future package recovery must target the existing `os_sr_cact_pkg` identity exactly once with a previously validated, unsigned package artifact and zero retries.
- Preserve the active package-backed handler and Custom API contract. Do not create a new PluginPackage, patch the handler or guard, modify the separate signed legacy rollback assembly, reactivate `ProtectCandidateCore`, inspect signing keys, enable Profiler, or change PluginTraceLog.
- Require immediate read-only topology reconciliation. If artifact identity or outcome is uncertain, stop; do not resend.
- A prior package artifact and release-specific one-shot rollback procedure have not been independently established for this ALM continuation. Do not infer the legacy signed assembly is an approved package rollback.
- `ModifiedOn` may be recorded when available but is not a mandatory success predicate. Server-readable package bytes are not assumed; use supported deployment acknowledgement and topology reconciliation without claiming a server-side content hash.

## External side effects and data

Candidate Core business writes are transactionally bounded, but a solution rollback does not undo email delivery, calendar events, SharePoint documents, source synchronization, or visitor registration. Those integrations remain outside the initial Candidate Core rehearsal unless separately approved with identity, idempotency, privacy, audit, and compensation controls.

Use synthetic records only. Do not use this plan to restore or reconcile real candidate data or to access ATSugg.

## Recovery acceptance

Recovery is accepted only after:

- the exact target and artifact identities are independently reconciled;
- a pre-import backup/baseline and prior approved release artifact set were verified;
- the Candidate Console and approved app load under the intended test identity;
- Candidate Core remains the only approved protected business-write path;
- direct protected writes remain denied by standard Dataverse privileges;
- synthetic workflow, idempotency, audit, privacy, and recovery checks pass; and
- no unexpected external side effects or unexplained record changes remain.

Production recovery requires separate incident, business, security, and change-control authorization. The current offline plan is ready; actual rollback remains blocked until its external evidence fields are populated and recovery is rehearsed.
