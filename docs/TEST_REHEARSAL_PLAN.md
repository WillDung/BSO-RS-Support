# Test Environment Rehearsal Plan

**Status (updated 2026-11-01):** The owner has explicitly authorized the bounded `LMV BI DEV` Test rehearsal; a sanitized session-local descriptor now validates as `TEST_TARGET_APPROVAL_EVIDENCE_SATISFIED`. This is not a claim that the complete release/import approval pack is complete. VN LMV BI (DEV) was previously reconciled as an enabled European Sandbox distinct from VN LMV IT Production, and a read-only baseline found no BSO-RS-Support Solution, `srapp`, project tables, Candidate Core Custom API, or Candidate Core package. A manual pre-deployment checkpoint was created and read back in the earlier qualification, but the exact target URL/IDs and checkpoint reference were not available in the current bounded continuation. A tenant-wide CLI result was not used for reconciliation. Post-integrity target WhoAmI, checkpoint readback, import-permission evidence, and current baseline are therefore `NOT VERIFIED`; no Test import or runtime test occurred. Offline forensic review established that the former aggregate source check included ignored build outputs; the corrected 171-file Git-index source inventory is pinned and repeatable, and `RELEASE_INPUT_INTEGRITY_RESTORED` closes that source blocker. A releaseable managed artifact, target-specific TEST configuration, effective import permission, and separate release/recovery/governance evidence remain unavailable. The offline [`Test-BsoRsTestRehearsalGate.ps1`](../scripts/Test-BsoRsTestRehearsalGate.ps1) reports owner authorization separately from these remaining gates.

The owner authorization applies only to the bounded LMV BI DEV Test rehearsal. It does not waive target requalification, import permission, artifact provenance, deployment identity, BSO test identity, recovery, governance, or release gates, and it does not authorize Production, unrelated environment resources, or real data. Follow [Master Production Rules](../MASTER_PRODUCTION_RULES.md), [ALM Deployment](ALM_DEPLOYMENT.md), the [Rollback Plan](ROLLBACK_PLAN.md), and the [Test Strategy](TEST_STRATEGY.md).

## 1. Test target approval pack

Owner authorization for the bounded rehearsal is recorded separately in sanitized session-local evidence. The following distinct target, release, identity, and recovery evidence is still required before an import; do not invent values or store target identifiers/real identities in canonical source:

- Environment display name, exact organization URL, Environment ID, Organization ID, and region.
- Fresh bounded confirmation that the environment is not Production business runtime.
- Verified deployment identity and effective permission to import/update BSO-RS-Support.
- A selected clean BSO Test identity and its separately verified approval/readiness.
- Synthetic-data authorization.
- Rollback/cleanup owner, pre-import backup/recovery evidence, and change/release approval.
- Approved managed-artifact hash, Solution unique name/version, and source provenance other than the DEV-origin review archive.

Evidence files must not contain credentials or tokens. The owner authorization descriptor does not include environment IDs/URLs, personal identities, tickets, or secrets. Gate output omits target identifiers, identities, and local evidence paths.

## 2. Entry gates

Record each item as `PASS`, `FAIL`, or `NOT VERIFIED`; stop on any failed gate.

- Previously authorized Test target requalified by its exact display name, URL, environment ID, organization ID, and region; verify licensing, capacity, backup/recovery posture, and DLP/privacy policy independently.
- Explicit evidence that the target is not Production business runtime.
- Fresh PAC `org who` and Dataverse `WhoAmI` agree with the approved Test target. Do not select or switch environments as part of this plan.
- Approved solution unique name, publisher/prefix, managed package hash, dependencies, and change/release approval.
- Candidate Console environment configuration generated outside the repository and verified for the approved Test target. Require `mode=TEST`, Candidate Core enabled, `syntheticDataOnly=true`, fallback disabled, and diagnostics `OFF`; the release-profile generator rejects deviations.
- Approved BSO-only Test identity manually authenticated in the browser. Confirm exact app, effective role, Candidate Core handler and DEV fallback state. Never request or automate credentials.
- Required audit, privacy, retention, access, DLP, support, and incident-response approvals recorded. These remain external prerequisites until independently verified; owner authorization permits synthetic data only.

## 3. Source and release preparation

1. Use the retained 72-root export mapping in [SOLUTION_COMPONENT_INVENTORY.json](SOLUTION_COMPONENT_INVENTORY.json); do not re-export or connect for this offline source task. The canonical source intentionally retains 20 releasable roots and excludes 50 inactive guard steps, two assembly roots, and the temporary DEV API.
2. Run [`Build-BsoRsPortableSolution.ps1`](../scripts/Build-BsoRsPortableSolution.ps1) for the unmanaged source round-trip. This does not produce a managed promotion artifact.
3. Generate any target-specific Candidate Console configuration outside the repository from an approved external profile. Do not copy the DEV-generated configuration or use identifiers embedded in historical evidence.
4. Build a managed release candidate only from reconciled source through an approved Test environment workflow. Current classification: `MANAGED_RELEASE_ARTIFACT_REQUIRES_APPROVED_TEST_REHEARSAL`; the DEV-origin managed export is explicitly `DEV_ORIGIN_REVIEW_ARTIFACT_NOT_RELEASEABLE`.
5. Confirm that deployment does not change the canonical workflow, operation receipt idempotency, Candidate ownership, actor attribution, fail-closed scheduling, email idempotency, audit, privacy, or ALM boundaries.

## 4. Controlled Test rehearsal

1. Verify the approved environment display name, exact organization URL, Environment ID, Organization ID, region, and fresh PAC `org who`/Dataverse `WhoAmI` agreement.
2. Verify the target is not Production business runtime; stop on mismatch or ambiguity.
3. Capture read-only baseline metadata and component inventory. Confirm no ambiguous existing release or incomplete prior import.
4. Import only the reviewed managed release candidate to the approved Test environment through the approved deployment mechanism. Do not use unmanaged source to promote downstream.
5. Apply only the separately approved target-specific configuration; verify Candidate Core enabled, synthetic-only mode, fallback disabled, and diagnostics Off.
6. Reconcile Solution identity/version/state, publisher, app module, web resources, Candidate Core package/handler, Custom API contract, environment configuration, connection references, and environment variables. For the existing `os_sr_cact_pkg`, use the bounded [package updater](../scripts/Update-BsoRsCandidatePluginPackage.ps1) only after the external target/artifact approvals pass. Its `Plan` mode is offline; `Apply` requires the approved target evidence, performs at most one existing-package dispatch with zero retries, and reconciles read-only. `Reconcile` is GET-only after an ambiguous outcome. The updater does not grant release approval or replace this rehearsal.
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
