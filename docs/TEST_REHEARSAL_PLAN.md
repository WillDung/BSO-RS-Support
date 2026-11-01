# Test Environment Rehearsal Plan

**Status (updated 2026-11-01):** Owner authorization for the bounded `LMV BI DEV` Test rehearsal is `TEST_TARGET_APPROVAL_EVIDENCE_SATISFIED`. It explicitly includes the current verified connected deployment identity for BSO-RS-Support import/export using existing privileges only (`TEST_DEPLOYMENT_IDENTITY_USE_APPROVED_FOR_BOUNDED_REHEARSAL`) and the existing checkpoint/recovery procedure with component-scoped recovery preferred (`TEST_RECOVERY_PROCEDURE_APPROVED_FOR_BOUNDED_REHEARSAL`). Fresh exact-target PAC `org who` and Dataverse `WhoAmI` previously agreed on VN LMV BI (DEV), a non-Production European Sandbox; checkpoint readback, clean BSO-RS-Support baseline, Global `prvImportCustomization`, canonical fingerprint, and external TEST configuration were verified. The checkpoint expires 8 November 2026. No BSO-RS-Support deployment write has occurred.

The current stop is `TEST_MANAGED_ARTIFACT_BOOTSTRAP_CLEANUP_BLOCKED`. PAC supports exporting a live unmanaged Solution as managed, and supports `pac solution delete`; however, Microsoft documents that deleting the unmanaged Solution removes only its container and leaves customizations in the Default Solution, and that the same environment cannot accept the managed Solution while its source unmanaged Solution remains. The canonical source cannot be packed directly as managed: PAC requires `Both` source from an earlier dual-package unpack, and the canonical snapshot is unmanaged-only; a prior managed-pack attempt failed. VN LMV IT cannot be mutated for this task. LMV BI DEV bootstrap could generate the artifact but the required clean-baseline restoration has no supported, verified, BSO-only component teardown. Therefore bootstrap import was not attempted, and there is no managed release artifact. Exact stop reason: `TEST_MANAGED_ARTIFACT_BOOTSTRAP_CLEANUP_BLOCKED:unmanaged solution deletion leaves customizations in the Default Solution, while same-environment managed import is unsupported; no approved BSO-only component teardown restores the pre-rehearsal baseline`.

Production audit/privacy/DLP, migration, integration launch scope, Production support ownership, and real-data authorization remain external Production gates only; none is marked satisfied. They do not block this synthetic Test workflow unless a freshly verified LMV BI DEV policy specifically prohibits it. No such policy prohibition has been verified. `REAL_DATA_STILL_PROHIBITED`. The offline rehearsal gate now checks deployment-identity/recovery authorization without requiring the later BSO test identity before managed topology reconciliation. Follow [Master Production Rules](../MASTER_PRODUCTION_RULES.md), [ALM Deployment](ALM_DEPLOYMENT.md), the [Rollback Plan](ROLLBACK_PLAN.md), and the [Test Strategy](TEST_STRATEGY.md).

## 1. Test target approval pack

Owner authorization covers BSO-RS-Support-only Test import/export in LMV BI DEV using the current verified connected deployment identity and existing privileges, plus the existing checkpoint/recovery procedure. This does not authorize Production, unrelated resources, privilege changes, or real data. The remaining pre-import requirements are:

- Fresh exact-target/checkpoint/baseline/source/configuration/permission preflight immediately before each external write.
- A supported managed-artifact path that can restore the original empty BSO-RS-Support baseline before final managed import. This remains the current blocker.
- Approved BSO-only component-scoped cleanup semantics if a bootstrap is proposed; deleting the unmanaged Solution container alone is insufficient.
- No BSO-only identity assignment until managed deployment topology is reconciled; select a clean identity afterward as specified below.

Evidence files must not contain credentials or tokens. Keep target IDs/URLs, personal identities, and local evidence paths out of canonical source and reports.

## 2. Entry gates

Record each item as `PASS`, `FAIL`, or `NOT VERIFIED`; stop on any failed gate.

- Previously authorized Test target requalified by its exact display name, URL, environment ID, organization ID, and region; verify licensing, capacity, backup/recovery posture, and DLP/privacy policy independently.
- Explicit evidence that the target is not Production business runtime.
- Fresh PAC `org who` and Dataverse `WhoAmI` agree with the approved Test target. Do not select or switch environments as part of this plan.
- Approved solution unique name, publisher/prefix, managed package hash, dependencies, and change/release approval.
- Candidate Console environment configuration generated outside the repository and verified for the approved Test target. Require `mode=TEST`, Candidate Core enabled, `syntheticDataOnly=true`, fallback disabled, and diagnostics `OFF`; the release-profile generator rejects deviations.
- Approved BSO-only Test identity manually authenticated in the browser. Confirm exact app, effective role, Candidate Core handler and DEV fallback state. Never request or automate credentials.
- Required audit, privacy, retention, access, DLP, support, and incident-response approvals recorded. These remain external prerequisites until independently verified; owner authorization permits synthetic data only.

## 3. Managed-artifact bootstrap and final Test deployment

The workflow has four distinct stages; an unmanaged bootstrap import is not Test acceptance:

1. **Canonical source:** use the 20 approved Solution roots from [SOLUTION_COMPONENT_INVENTORY.json](SOLUTION_COMPONENT_INVENTORY.json); exclude 50 inactive guard steps, both assembly roots, and temporary `os_sr_devcs`. Run [`Build-BsoRsPortableSolution.ps1`](../scripts/Build-BsoRsPortableSolution.ps1) for source integrity only; it creates an unmanaged round-trip, not a managed release artifact. Do not edit Solution XML to fabricate managed state.
2. **Managed-artifact path selection:** Path A (`pac solution pack --packagetype Managed`) is unavailable from the current source because PAC requires a previous `Both` unpack and the current source has only unmanaged files; the attempt was unsuccessful. Path B (managed export from VN LMV IT) is out of scope and not authorized. Path C (unmanaged bootstrap import to LMV BI DEV, then PAC managed export) is owner-authorized but must not begin unless a supported BSO-only cleanup has been demonstrated to restore the initial baseline and permit final managed import.
3. **Bootstrap, only after cleanup proof:** reverify exact target, recovery checkpoint, clean BSO baseline, source fingerprint, TEST config, and deployment identity capability. Import only `os_sr_bso_rs_support` unmanaged with zero retries and no `PublishAllXml`; use TEST configuration or fail-closed UNCONFIGURED state. Export the same Solution as managed, validate identity/version/managed flag, exact 20-root inventory, package/API/app/schema/role/web-resource content, absence of inactive guard roots and signed legacy handler, no unexpected components or DEV target leakage, then freeze SHA-256. Record `TEST_MANAGED_ARTIFACT_BOOTSTRAP_IMPORT` and `TEST_MANAGED_RELEASE_ARTIFACT_BUILT`; this is not acceptance.
4. **Restore baseline then final managed deployment:** prove the supported cleanup removes all BSO-RS-Support bootstrap components without touching unrelated resources; read back the original empty baseline; import the pinned managed artifact with zero retries. Only this managed deployment can enter runtime acceptance. If the cleanup proof cannot be established, stop as `TEST_MANAGED_ARTIFACT_BOOTSTRAP_CLEANUP_BLOCKED:<EXACT_REASON>`.

## 4. Controlled Test rehearsal after baseline restoration

1. Freshly verify exact approved target and clean baseline; stop on any mismatch.
2. Import only the pinned managed artifact, retries zero, no `PublishAllXml`. On ambiguous result return `SOLUTION_IMPORT_OUTCOME_AMBIGUOUS_REQUIRES_RECONCILIATION` and stop mutation.
3. Apply only the approved target-specific TEST configuration. Verify mode TEST, synthetic-only, Candidate Core enabled, DEV fallback unavailable, diagnostics Off, and exact target accepted.
4. Reconcile managed Solution identity, `srapp`, schema, BSO role definition, web resources, API, package/handler, inactive guards, absence of active Profiler, and unchanged PluginTraceLog. Use the existing package updater only if read-only reconciliation proves an update is required; one dispatch maximum, retries zero.
5. After topology reconciliation, inventory a clean BSO-only test identity. If none exists, stop `TEST_BSO_IDENTITY_REQUIRED`; do not strip existing elevated rights. Assign only the BSO role once if absent; verify `srapp` association.
6. Manually authenticate as that BSO identity; verify WhoAmI, exact app, TEST synthetic-only configuration, active Candidate Core, and unavailable fallback.
7. Create only minimum synthetic reference fixtures if required; use `.invalid` email addresses.
8. Run the positive lifecycle, idempotency/conflict/stale-status checks, and five direct-write negatives exactly as specified below.
9. Exercise only the approved component-level Test recovery when safely scoped; whole-environment restore is not routine cleanup and is allowed only under the explicit conditions in the owner authorization.
7. Establish the approved BSO role/app access; authenticate manually as the approved BSO test identity and verify `WhoAmI` and effective roles.
8. Confirm the browser loads exact `srapp` and current approved resource hashes.
9. Use synthetic data only. Execute the approved Candidate Core lifecycle and read-only reconciliation:
   - Create Candidate.
   - Record Call = Answered.
   - Move to Waiting Manual Scheduling.
   - Schedule Round 1.
   - Verify Candidate status/owner, Call Log, Status History, Interview Schedule, Operation Receipt evidence, and reference selectors.
10. Exercise replay/idempotency, conflicting replay, and stale-status rejection using the approved synthetic cases. Reconcile each result read-only; do not retry an uncertain operation.
11. Only after the positive lifecycle passes, attempt once each outside Candidate Core: Candidate Create, Candidate Update, Call Log Create, Status History Create, and Interview Schedule Create. Require standard Dataverse privilege denials. Stop immediately on any success; do not retry.
12. Exercise the approved rollback/recovery path against the exact captured prior artifacts and configuration. Do not reactivate `ProtectCandidateCore` or remap to the signed legacy assembly.
13. Perform final read-only reconciliation of Solution/package/handler topology, app/resources/configuration, role boundary, business/evidence rows, receipts, and audit/release evidence; ensure no retries, duplicates, partial/uncertain operations, unexpected audit changes, or real data.

## 5. Rollback and stop conditions

- Stop on target mismatch, missing/ambiguous components, import errors, identity or role mismatch, unexpected fallback, unsafe data mode, failed idempotency, any direct-write success, uncertain external side effect, or unexplained record delta.
- Preserve the evidence journal and sanitized failure stage; never reuse an evidence path or repeat a non-idempotent dispatch without reconciliation and explicit authorization.
- For an application/web-resource failure, restore only the pre-approved, captured resource versions through the scoped deployment workflow and reconcile the exact resources and app. Do not use `PublishAllXml`.
- For a managed Solution failure, follow the approved Test recovery plan using the prior reviewed managed version or environment restore process. A prior artifact, backward-compatible upgrade path, and tested recovery procedure are prerequisites; none is asserted here.
- Never restore Production, reactivate `ProtectCandidateCore`, grant table privileges as a workaround, modify the legacy rollback assembly, or change PluginTraceLog/Profiler state as part of this rehearsal.

## 6. Exit report

The rehearsal report must include the approved target label (no raw IDs), artifact hash, solution version, browser identity classification, exact app/resource versions, each gate result, lifecycle results, five direct-write outcomes, sanitized failures, record reconciliation counts, audit/DLP/privacy results, rollback readiness, and unresolved dependencies. Do not include tokens, credentials, environment identifiers, candidate PII, CVs, or raw connector URLs.

Final disposition must be one of:

- `TEST_REHEARSAL_ACCEPTED`
- `TEST_REHEARSAL_FAILED:<SAFE_STAGE>`
- `TEST_TARGET_APPROVAL_EVIDENCE_SATISFIED` (owner authorization only; not full import approval)
- `TEST_RELEASE_READINESS_EVIDENCE_REQUIRED`
- `TEST_REHEARSAL_NOT_VERIFIED`

Test acceptance is not Production approval. Production requires a separate readiness review and release authorization.
