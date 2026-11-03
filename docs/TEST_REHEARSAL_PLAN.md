# Test Environment Rehearsal Plan

**Status (updated 2026-11-02):** Owner authorization for the bounded `LMV BI DEV` Test rehearsal, current connected deployment identity (existing privileges only), and existing checkpoint/recovery procedure remains in effect. The owner has also authorized the existing VN LMV IT `os_sr_bso_rs_support` Solution as the managed-artifact source, limited to temporary fail-closed Candidate Console configuration/HTML changes, `PublishXml` scoped to exactly the changed WebResource IDs (no `srapp` and no `PublishAllXml`), one managed export, and exact restoration of captured source-resource bytes. LMV BI DEV remains the final managed Test target. This supersedes the earlier restriction that VN LMV IT could not be used as an artifact source; it does not authorize other source-environment changes.

**Update (2026-11-03):** The release-neutral update, WebResource-only publication (no `srapp`), single Managed export, and mandatory restoration are complete. The frozen 21-root artifact (SHA-256 `33c491f84d8082817e0be888889fd6239a6bdb5bc76c01bdcb5040cdc11f9970`) is `RELEASEABLE_MANAGED_ARTIFACT_BUILT`. LMV BI DEV requalification passed for target, Sandbox type, `WhoAmI`, checkpoint, and clean baseline. It failed import capability because `prvImportCustomization` is no longer effective, so no import or rehearsal step had run at that point (superseded by the progress entry below). The revised model is `OPERATOR_ASSISTED_TEST_IMPORT`:

- An authorized LMV BI DEV operator imports only the frozen artifact under the handoff constraints.
- Copilot verifies the post-import 21-root topology read-only.
- TEST configuration and BSO role assignment use bounded operator micro-handoffs if the Copilot identity lacks those rights.
- No privilege is granted to the Copilot/deployment identity.

The pre-import baseline is `OPERATOR_ASSISTED_IMPORT_BASELINE_READY`. The historical snapshot paragraph below describes the state before these updates.

**Progress (2026-11-03, later):** The frozen artifact was imported once into LMV BI DEV and reconciled read-only (`TEST_OPERATOR_IMPORT_RECONCILED`, `TEST_MANAGED_DEPLOYMENT_TOPOLOGY_VERIFIED`). The TEST configuration was applied through the scoped WebResource-only path and verified (`TEST_CONFIGURATION_RUNTIME_VERIFIED`). Package writes were 0 (`TEST_CANDIDATE_CORE_PACKAGE_RECONCILED`). The deployment identity is privileged through team membership and is excluded from BSO acceptance. One clean user was identified. The owner approved exactly one `BSO-RS Support - BSO` assignment, which is verified with clean effective access (`TEST_BSO_ROLE_ASSIGNMENT_VERIFIED`). The rehearsal stopped at `TEST_BSO_BROWSER_IDENTITY_REQUIRED`. Steps 4-13 below require manual browser authentication as that user and a confirmed `WhoAmI`. VN LMV IT is quarantined from writes after `VN_LMV_IT_PUBLICATION_STATE_AMBIGUITY_RECORDED`. See [CURRENT_STATE.md](CURRENT_STATE.md).

**Historical snapshot (before the 2026-11-03 updates above; superseded):** The exact VN LMV IT source and `srapp` were verified, and all five canonical Candidate Console resources passed published/current/effective hash equivalence and source qualification. The first Managed export was rejected because it contained 72 roots and the `os_sr_devcs` non-root membership. The owner-directed membership-only cleanup is now readback-verified: the live Solution contains 21 expected roots and 47 memberships; 51 excluded-root and 15 temporary API-group memberships were removed without deleting component records. A new release-neutral update, WebResource-only publication, managed export, and mandatory resource restoration remain pending. Both prior temporary `PublishXml` requests included `srapp`; its pre-call publication state was not captured, so the possible app publication remains unknown. Do not include `srapp` or use `PublishAllXml` in any subsequent publication. No new export or LMV BI DEV import has occurred since the cleanup. The existing `TEST_MANAGED_ARTIFACT_BOOTSTRAP_CLEANUP_BLOCKED` applies only to the abandoned LMV BI DEV unmanaged-bootstrap/same-environment-export route. No managed release artifact currently exists.

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

1. **Canonical source:** retain the 20 authored roots in `Solution.xml`; the release composition is those roots plus the one unsigned PluginAssembly generated from the retained `os_sr_cact_pkg`, for 21 roots. Exclude the signed rollback-only assembly and 50 inactive guard-step roots (51 total), and exclude the separate non-root `os_sr_devcs` Custom API membership group. Preserve the package membership and generated assembly. Run [`Build-BsoRsPortableSolution.ps1`](../scripts/Build-BsoRsPortableSolution.ps1) for source integrity only; it creates an unmanaged round-trip, not a managed release artifact. Do not edit Solution XML to fabricate managed state.
2. **Fresh source preflight:** freshly verify VN LMV IT URL/environment/organization identity, PAC and Dataverse identity agreement, accepted Solution/`srapp`/Candidate Core topology, and all pinned release inputs. Capture exact published bytes, hashes, resource IDs, and `srapp` identity for only the environment-config and HTML resources outside canonical source. Stop on any mismatch, pending unpublished resource, or release-input drift.
3. **Temporary release-neutral export:** generate an `UNCONFIGURED` profile with empty target bindings, Candidate Core disabled, synthetic-only mode, fallback disabled, and diagnostics Off; hash-bust only the matching HTML. Offline-validate the policy, exact resource selection, and absence of target IDs/URLs/secrets/PII. Refresh only those two existing resources and scope `PublishXml` to exactly their WebResource IDs, with zero retries; do not include `srapp` or use `PublishAllXml`. GET-reconcile exact bytes, then export `os_sr_bso_rs_support` once as Managed from VN LMV IT. No import or package update occurs in the source environment.
4. **Validate and freeze:** validate the exported managed ZIP's identity/version/publisher, managed flag, exact 21-root release composition, dependencies, app/sitemap, schema and metadata, BSO role, API/package topology, Console assets/configuration, absence of target leakage, exclusion of the 50 inactive guard roots and signed rollback assembly, and absence of the `os_sr_devcs` membership group. Compare exported components with the canonical-source inventory. If any expected component or exclusion cannot be proven, do not release the artifact.
5. **Mandatory source restoration:** whether export succeeds or fails, restore the exact captured pre-change environment-config and HTML bytes and publish only their exact WebResource IDs, with zero retries and no `srapp` or `PublishAllXml`. Reconcile byte hashes, JS/CSS/policy hashes, app identity, package/API/schema/security topology, and no business-data delta. Stop as `VN_LMV_IT_RELEASE_SOURCE_RESTORE_FAILURE` if exact restoration cannot be proven.
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
