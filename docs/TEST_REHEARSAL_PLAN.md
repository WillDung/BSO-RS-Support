# Test Environment Rehearsal Plan

**Status:** Proposed; not executed. No approved Test environment or target-specific configuration is established. Current gate: `TEST_TARGET_APPROVAL_REQUIRED`. The offline [`Test-BsoRsTestRehearsalGate.ps1`](../scripts/Test-BsoRsTestRehearsalGate.ps1) validates external approval evidence and a managed-artifact hash only; it performs no authentication, import, or runtime test.

This plan does not authorize an environment connection, import, role change, integration enablement, real-data use, or Production operation. It is an executable sequence only after the owner approves a Test target, release artifact, and test identity. Follow [Master Production Rules](../MASTER_PRODUCTION_RULES.md), [ALM Deployment](ALM_DEPLOYMENT.md), the [Rollback Plan](ROLLBACK_PLAN.md), and the [Test Strategy](TEST_STRATEGY.md).

## 1. Entry gates

Record each item as `PASS`, `FAIL`, or `NOT VERIFIED`; stop on any failed gate.

- Owner-approved Test environment URL, environment ID, organization ID, region, licensing, capacity, backup/recovery posture, and DLP/privacy policy.
- Fresh PAC `org who` and Dataverse `WhoAmI` agree with the approved Test target. Do not select or switch environments as part of this plan.
- Approved solution unique name, publisher/prefix, managed package hash, dependencies, and change/release approval.
- Candidate Console environment configuration generated outside the repository and verified for the approved Test target. Require `mode=TEST`, Candidate Core enabled, `syntheticDataOnly=true`, fallback disabled, and diagnostics `OFF`; the release-profile generator rejects deviations.
- Approved BSO-only Test identity manually authenticated in the browser. Confirm exact app, effective role, Candidate Core handler and DEV fallback state. Never request or automate credentials.
- Required audit, privacy, retention, access, DLP, support, and incident-response approvals recorded. These remain external prerequisites until independently verified.

## 2. Source and release preparation

1. Use the retained 72-root export mapping in [SOLUTION_COMPONENT_INVENTORY.json](SOLUTION_COMPONENT_INVENTORY.json); do not re-export or connect for this offline source task. The canonical source intentionally retains 20 releasable roots and excludes 50 inactive guard steps, two assembly roots, and the temporary DEV API.
2. Run [`Build-BsoRsPortableSolution.ps1`](../scripts/Build-BsoRsPortableSolution.ps1) for the unmanaged source round-trip. This does not produce a managed promotion artifact.
3. Generate any target-specific Candidate Console configuration outside the repository from an approved external profile. Do not copy the DEV-generated configuration or use identifiers embedded in historical evidence.
4. Build a managed release candidate only from reconciled source through an approved Test environment workflow. Current gate: `MANAGED_BUILD_REQUIRES_APPROVED_TEST_ENVIRONMENT`; the DEV-origin managed export is not acceptable.
5. Confirm that deployment does not change the canonical workflow, operation receipt idempotency, Candidate ownership, actor attribution, fail-closed scheduling, email idempotency, audit, privacy, or ALM boundaries.

## 3. Controlled Test rehearsal

1. Capture read-only baseline metadata and component inventory. Confirm no ambiguous existing release or incomplete prior import.
2. Import only the reviewed managed release candidate to the approved Test environment through the approved deployment mechanism. Do not use unmanaged source to promote downstream.
3. Reconcile Solution identity/version/state, publisher, app module, web resources, Candidate Core package/handler, Custom API contract, environment configuration, connection references, and environment variables.
4. Confirm the Test browser loads the exact approved app and current resource hashes. Authenticate manually as the approved BSO test identity; verify `WhoAmI` and effective roles before runtime tests.
5. Use synthetic data only. Execute the approved Candidate Core lifecycle and read-only reconciliation:
   - Create Candidate.
   - Record Call = Answered.
   - Move to Waiting Manual Scheduling.
   - Schedule Round 1.
   - Verify Candidate status/owner, Call Log, Status History, Interview Schedule, Operation Receipt evidence, and reference selectors.
6. Only after the positive lifecycle passes, attempt once each outside Candidate Core: Candidate Create, Candidate Update, Call Log Create, Status History Create, and Interview Schedule Create. Require standard Dataverse privilege denials. Stop immediately on any success; do not retry.
7. Test only integrations explicitly included in the release and separately approved. Email/calendar, SharePoint/CV storage, LEGO Careers synchronization, visitor registration, and other external integrations remain excluded from this Candidate Core rehearsal unless their own identity, DLP, idempotency, privacy, and recovery gates are approved.
8. Reconcile records and operation receipts read-only; ensure no retries, duplicates, partial/uncertain operations, unexpected audit changes, or real data.

## 4. Rollback and stop conditions

- Stop on target mismatch, missing/ambiguous components, import errors, identity or role mismatch, unexpected fallback, unsafe data mode, failed idempotency, any direct-write success, uncertain external side effect, or unexplained record delta.
- Preserve the evidence journal and sanitized failure stage; never reuse an evidence path or repeat a non-idempotent dispatch without reconciliation and explicit authorization.
- For an application/web-resource failure, restore only the pre-approved, captured resource versions through the scoped deployment workflow and reconcile the exact resources and app. Do not use `PublishAllXml`.
- For a managed Solution failure, follow the approved Test recovery plan using the prior reviewed managed version or environment restore process. A prior artifact, backward-compatible upgrade path, and tested recovery procedure are prerequisites; none is asserted here.
- Never restore Production, reactivate `ProtectCandidateCore`, grant table privileges as a workaround, modify the legacy rollback assembly, or change PluginTraceLog/Profiler state as part of this rehearsal.

## 5. Exit report

The rehearsal report must include the approved target label (no raw IDs), artifact hash, solution version, browser identity classification, exact app/resource versions, each gate result, lifecycle results, five direct-write outcomes, sanitized failures, record reconciliation counts, audit/DLP/privacy results, rollback readiness, and unresolved dependencies. Do not include tokens, credentials, environment identifiers, candidate PII, CVs, or raw connector URLs.

Final disposition must be one of:

- `TEST_REHEARSAL_ACCEPTED`
- `TEST_REHEARSAL_FAILED:<SAFE_STAGE>`
- `TEST_TARGET_APPROVAL_REQUIRED`
- `TEST_REHEARSAL_NOT_VERIFIED`

Test acceptance is not Production approval. Production requires a separate readiness review and release authorization.
