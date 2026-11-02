# Test Environment Rehearsal Plan

**Status (updated 2026-11-02):** Owner authorization for the bounded `LMV BI DEV` Test rehearsal, current connected deployment identity (existing privileges only), and existing checkpoint/recovery procedure remains in effect. The owner has also authorized the existing VN LMV IT `os_sr_bso_rs_support` Solution as the managed-artifact source, with only temporary fail-closed Candidate Console configuration/HTML changes, exact-resource/app-scoped publication, one managed export, and exact restoration of the captured source resources. LMV BI DEV remains the final managed Test target. This supersedes the earlier restriction that VN LMV IT could not be used as an artifact source; it does not authorize other source-environment changes.

The source path is stopped at `CANDIDATE_CONSOLE_PUBLICATION_OUTCOME_AMBIGUOUS`. Fresh PAC/Dataverse identity, Solution, and app checks matched VN LMV IT. All five canonical Candidate Console resources matched their accepted current/published hashes before one scoped PublishXml (HTTP 204). GET readback still reports all five `Unpublished`, with hashes unchanged. The one-shot journal records PublishXml=1, resource PATCH=0, resource POST=0, sitemap PATCH=0, retries=0. GET-only reconciliation confirmed the unresolved state; do not retry or continue to release-neutral updates/export without new bounded authorization and resolution of the publication behavior. No export, restoration, or import occurred. The existing `TEST_MANAGED_ARTIFACT_BOOTSTRAP_CLEANUP_BLOCKED` applies only to the abandoned LMV BI DEV unmanaged-bootstrap/same-environment-export route. No managed release artifact currently exists.

Production audit/privacy/DLP, migration, integration launch scope, Production support ownership, and real-data authorization remain external Production gates only; none is marked satisfied. They do not block this synthetic Test workflow unless a freshly verified LMV BI DEV policy specifically prohibits it. No such policy prohibition has been verified. `REAL_DATA_STILL_PROHIBITED`. The offline rehearsal gate now checks deployment-identity/recovery authorization without requiring the later BSO test identity before managed topology reconciliation. Follow [Master Production Rules](../MASTER_PRODUCTION_RULES.md), [ALM Deployment](ALM_DEPLOYMENT.md), the [Rollback Plan](ROLLBACK_PLAN.md), and the [Test Strategy](TEST_STRATEGY.md).

## 1. Test target approval pack

Owner authorization covers BSO-RS-Support-only Test import/export in LMV BI DEV using the current verified connected deployment identity and existing privileges, plus the existing checkpoint/recovery procedure. This does not authorize Production, unrelated resources, privilege changes, or real data. The remaining pre-import requirements are:

- Fresh exact-target/checkpoint/baseline/source/configuration/permission preflight immediately before each external write.
- Fresh exact-source and final-target identity qualification, and exact baseline byte capture for the two permitted VN LMV IT Candidate Console resources.
- A release-neutral managed export that passes canonical-source, dependency, configuration-leak, package/API/app/schema/role/web-resource, and inactive-guard validation.
- Exact restoration and readback of the captured VN LMV IT resources before any LMV BI DEV operation.
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

## 3. Managed-artifact source export and final Test deployment

The approved path exports the existing Solution from VN LMV IT without importing or changing its Solution/package/schema/security/business data. The separate LMV BI DEV managed deployment begins only after the source export is validated and the source resources are restored:

1. **Canonical source:** use the 20 approved Solution roots from [SOLUTION_COMPONENT_INVENTORY.json](SOLUTION_COMPONENT_INVENTORY.json); exclude 50 inactive guard steps, both assembly roots, and temporary `os_sr_devcs`. Run [`Build-BsoRsPortableSolution.ps1`](../scripts/Build-BsoRsPortableSolution.ps1) for source integrity only; it creates an unmanaged round-trip, not a managed release artifact. Do not edit Solution XML to fabricate managed state.
2. **Fresh source preflight:** freshly verify VN LMV IT URL/environment/organization identity, PAC and Dataverse identity agreement, accepted Solution/`srapp`/Candidate Core topology, and all pinned release inputs. Capture exact published bytes, hashes, resource IDs, and `srapp` identity for only the environment-config and HTML resources outside canonical source. Stop on any mismatch, pending unpublished resource, or release-input drift.
3. **Temporary release-neutral export:** generate an `UNCONFIGURED` profile with empty target bindings, Candidate Core disabled, synthetic-only mode, fallback disabled, and diagnostics Off; hash-bust only the matching HTML. Offline-validate the policy, exact resource selection, and absence of target IDs/URLs/secrets/PII. Refresh only those two existing resources and scope `PublishXml` to them and `srapp`, with zero retries. GET-reconcile exact bytes, then export `os_sr_bso_rs_support` once as Managed from VN LMV IT. No import or package update occurs in the source environment.
4. **Validate and freeze:** validate the exported managed ZIP's identity/version/publisher, managed flag, canonical 20-root release inventory, dependencies, app/sitemap, schema and metadata, BSO role, API/package topology, Console assets/configuration, absence of target leakage, 50 inactive guard roots, and rollback-only signed assembly disposition. Compare exported components with the canonical-source inventory. If any expected component or exclusion cannot be proven, do not release the artifact.
5. **Mandatory source restoration:** whether export succeeds or fails, restore the exact captured pre-change environment-config and HTML bytes, publish only those resources and `srapp`, and reconcile byte hashes, JS/CSS/policy hashes, app identity, package/API/schema/security topology, and no business-data delta. Stop as `VN_LMV_IT_RELEASE_SOURCE_RESTORE_FAILURE` if exact restoration cannot be proven.
6. **Final managed Test deployment:** only after `RELEASEABLE_MANAGED_ARTIFACT_BUILT` and `VN_LMV_IT_RELEASE_SOURCE_RESTORED`, freshly requalify LMV BI DEV, checkpoint, baseline, TEST configuration, import capability, and approval evidence. Import only the frozen managed artifact with zero retries and no `PublishAllXml`/dependency bypass. The former same-environment unmanaged-bootstrap cleanup blocker does not apply to this source-export path.

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
