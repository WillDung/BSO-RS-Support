# Scripts

## Phase 3C receipt and API metadata

[Provision-BsoRsOperationReceipt.ps1](Provision-BsoRsOperationReceipt.ps1) defaults to `PlanOnly` with zero authentication/network calls. `Preflight` / `Reconcile` are GET-only guarded modes. Its receipt-only create/correction modes are bounded to the owner-approved table, Candidate relationship, canonical String alternate key, and two exact metadata property corrections observed during provisioning. Consumed create/correction dispatches must never be repeated. Existing receipt metadata requires `Reconcile`, not `Apply`. Historical completion modes are pinned to their retained dispatch evidence and exact known intermediate metadata.

[Deploy-BsoRsCandidateOperations.ps1](Deploy-BsoRsCandidateOperations.ps1) supports explicit `Preflight`, `Apply`, and `Reconcile`. It first runs full guarded Candidate Core/receipt reconciliation. Preflight discovers exact SDK registration navigation/message filters and saves a new local write plan with assembly/contract/storage/body fingerprints. Apply requires its exact hash and a new durable dispatch journal; it reserves each dispatch before sending, GET-reconciles immediately, and stops on failure/uncertainty with zero automatic retries. It never invokes `os_sr_cact`, creates business rows, grants roles, changes the app, or publishes.

Do not blindly rerun Apply after any partial registration. Use the retained journal and read-only reconciliation before obtaining any required bounded continuation. See [plug-in build instructions](../solutions/CandidateCore/README.md), [receipt plan](../docs/PHASE_3C_OPERATION_RECEIPT_PLAN.json), [API contract](../docs/PHASE_3C_API_CONTRACT.json), and [current Phase 3C report](../docs/PHASE_3C_CANDIDATE_CORE_API_PLUGIN_REPORT.md).

Scripts here support reviewed build, validation, migration, and ALM tasks. They must be safe by default, avoid embedded credentials and personal data, clearly identify environment effects, and include verification instructions.

## Existing Candidate Core package update

[Update-BsoRsCandidatePluginPackage.ps1](Update-BsoRsCandidatePluginPackage.ps1) is the canonical one-shot dispatcher for the existing `os_sr_cact_pkg`; do not use the historical package-create runner for release updates. `Plan` validates the frozen local unsigned package offline. `Apply` is gated by external target/release evidence, PAC/Dataverse identity agreement, and read-only package/handler/API/guard/legacy reconciliation; it reserves a new journal before one structured `pac plugin push`, permits zero retries, and never creates a package or changes handler, guard, legacy assembly, signing, trace, Profiler, or publication state. `Reconcile` accepts only a matching ambiguous/reserved journal, validates target identity fingerprints before connecting, performs GET-only reconciliation, and never resends. Offline tests do not establish deployment or target approval.

## Candidate Console scoped refresh

[Deploy-BsoRsCandidateConsole.ps1](Deploy-BsoRsCandidateConsole.ps1) supports an existing-resource refresh with `-RefreshExisting`. `-RefreshResourceNames` can narrow that mode to exact existing resources from the fixed Candidate Console allowlist; it is rejected outside a fresh refresh and cannot be combined with continuation. The selected resource IDs alone are included in scoped `PublishXml` alongside `srapp`; the refresh does not patch the sitemap. Without the selector, its default existing-resource set remains the original three Candidate Console resources. Every selected resource is read back and reconciled, automatic retries are zero, and uncertain writes stop without retry.

[New-BsoRsCandidateConsoleEnvironmentConfig.ps1](New-BsoRsCandidateConsoleEnvironmentConfig.ps1) generates a target-specific configuration JavaScript file and matching cache-busted HTML copy outside the repository. Bound DEV/TEST/PROD modes require explicit organization URL, environment ID, and organization ID inputs; DEV/TEST must remain synthetic-only, and direct-write fallback is DEV-only. `UNCONFIGURED` is release-neutral only when all target bindings are empty, Candidate Core and direct-write fallback are disabled, data remains synthetic-only, and diagnostics are Off. Generated files are not source artifacts and must not be committed or stored in the repository.

The scoped deploy script's `-CreateNewResources` mode is restricted to creating the exact environment-configuration and policy web resources, verifies the generated configuration against its fixed VN LMV IT DEV target, preserves the existing sitemap, and scopes publication to those resources plus `srapp`. A release-neutral refresh is separately gated by `-ReleaseNeutralProfile`, `-RefreshExisting`, and the exact existing environment-configuration and HTML resources; it rejects target bindings or enabled Candidate Core and does not permit a sitemap, JS, CSS, policy, schema, API, package, or role change. To deploy a changed configuration, refresh the exact existing environment and HTML resources together with `-EnvironmentConfigurationPath` and `-EnvironmentHtmlPath`; the latter must match checked-in HTML except for the verified configuration hash token. `-BaselineSnapshotPath` is limited to a fresh read-only preflight with a new external path and captures both effective and directly published bytes/hashes. The preflight is ready only when both resources are published and their effective bytes exactly match the published bytes; an unpublished resource remains a hard stop even when its bytes are equal. A diagnostic snapshot does not authorize overwriting or publishing pending drafts. Before an authorized refresh, preserve the accepted pre-change bytes; after export, restore and reconcile those exact bytes before continuing. Candidate Console browser acceptance still requires fresh approved-BSO identity verification. No TEST target or Production configuration is established by these tools.

## Phase 5A Candidate Core runtime acceptance

[Test-BsoRsCandidateCorePhase5A.ps1](Test-BsoRsCandidateCorePhase5A.ps1) is a separate, bounded VN LMV IT runtime runner; it does not reuse the historical Phase 3D guard-focused runner. `PlanOnly` verifies the active PAC/Az identity, `os_sr_cact` execution privilege, entity metadata, active `[DEV]` TA/Location references, and zero-row gates for fresh synthetic `.invalid` Candidates and operation correlations. `Apply` is explicitly pinned to VN LMV IT, allows exactly 27 Custom API POSTs with zero retries, reserves each call in a new evidence journal, and writes only through `os_sr_cact`. The matrix covers Answered, No Answer, Call Back Requested, Waiting Manual Scheduling, Schedule, Pass, Fail, Reschedule, Cancel, identical/conflicting replay, and stale ExpectedStatus; it reads back only the four synthetic Candidates and their related records. It does not create, delete, publish, assign roles, or inspect/reopen ProtectCandidateCore registrations. An uncertain or rejected unexpected operation stops the run; do not reuse an evidence path or automatically rerun a partially dispatched matrix.

[Repair-BsoRsCandidateCoreApiInputs.ps1](Repair-BsoRsCandidateCoreApiInputs.ps1) is a separate, one-shot repair for the existing `os_sr_cact` Custom API in VN LMV IT. It validates the existing `os_sr_bso_rs_support` Solution, `os` Publisher, API execution privilege, and the complete local request-parameter contract. Its only allowed additions are the five currently missing optional schedule/result inputs. `Preflight` writes a new pinned local plan, `Apply` requires that plan hash and a new evidence path and reconciles each POST immediately, and `Reconcile` is GET-only. It does not update the plug-in package, change role privileges, publish, write business records, or touch guard registrations.

## Phase 3D synthetic runtime acceptance

[Test-BsoRsCandidateCoreRuntime.ps1](Test-BsoRsCandidateCoreRuntime.ps1) has a GET-only `Preflight` mode and separately authorized bounded Apply modes for at most one `[SYNTHETIC-E2E]` Candidate and eight Custom API dispatches; automatic retries are fixed at zero. Apply requires a new empty evidence file, a fresh zero-row gate, and a durable one-shot lock. Historical R4M runtime authorization and its rejected `CALLER_MARKER` CreateCandidate are consumed; they are not current status or reusable. The current R4O server-registration runtime one-shot and its rejected `UNSUPPORTED_GUARD_REGISTRATION` CreateCandidate are documented below. Do not remove consumed locks or rerun any Apply mode. See the [Phase 3D report](../docs/PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

## Existing R4O server-registration classifier

The current source classifies protected table writes from the current guard's server-owned OwningExtension and read-only active step/handler/assembly/package/message/filter metadata. Runtime message/entity values are consistency checks only. The ActionType/write allowlist and verified API ancestor trust remain separate and unchanged. `Get-GuardRegistrationInventory` in the GET-only `Preflight` mode enumerates each package-backed guard's step name, SDK message, table filter and canonical WriteCode; only six exact table/message pairs map, exact unsupported pairs remain fail-closed, and Associate/Disassociate remain relationship guards. Fresh preflight resolved 50/50 registrations (six canonical, 42 unsupported, two relationship) with no unresolved or contradictory rows and counts 0/0/0/0. See the full inventory and local validation in the [Phase 3D report](../docs/PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

The existing `os_sr_cact_pkg` was updated exactly once with PAC CLI `pac plugin push`; the package identity remained stable, its `modifiedon` advanced, and immediate read-only preflight reconciled the package-backed handler/guard and 50-step topology. One `R4OServerRegistrationApply` runtime one-shot dispatched a single CreateCandidate with retries disabled. The safe result was `DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_GUARD_REGISTRATION:CC_CREATE_CANDIDATE:0x80040265`. The guard's exact internal metadata check is not identified by that category. No matrix, direct-write canary, second update/call, or further backend diagnostic ran. The evidence journal is retained; do not rerun or clear its authorization. The last confirmed counts were 0/0/0/0 before deployment; post-call counts were not re-read after the stop.

## Phase 3D-R4L Candidate Core guard cutover

This historical R4L procedure superseded older R4K runtime-lock and dispatch-count notes. The current R4M outcome is documented below; do not repeat the R4L cutover or runtime authorization.

[Cutover-BsoRsCandidateCoreGuards.ps1](Cutover-BsoRsCandidateCoreGuards.ps1) defaults to GET-only `Preflight`. It reconciles the existing package, package/legacy guard types, Candidate Core Custom API handler, exact message/table guard-step inventory, protected step-property fingerprints, unsecure-configuration hashes, secure-configuration relationship IDs only, and Solution memberships. It writes a local rollback map to a new caller-selected file before any registration PATCH; the map contains environment-specific IDs and must remain in protected local session storage, not be committed or shared.

Only `Apply`, `Continue`, and `Rollback` can PATCH, and only an existing `sdkmessageprocessingstep` EventHandler relationship. Each step gets at most one PATCH per direction, reserved in a durable journal before dispatch and immediately GET-reconciled; transport ambiguity stops the run with zero automatic retries. `Reconcile` is GET-only. `Continue` requires pinned prior evidence and a fresh per-step topology match. It handles the initial null-to-empty configuration-hash journal coercion only when the prior HTTP 2xx, handler, protected-property digest, and membership all reconcile. For an interrupted continuation, it also requires the pinned root journal and exact predecessor state (14 reconciled, one reserved-before-dispatch, 34 untouched in the current R4L recovery); it proves every prior step's live handler, requires the reserved request count to equal the completed readbacks, and writes only the remaining legacy-backed entries to a new journal. It never retries or edits prior evidence. `Rollback` uses the exact original handler IDs and protected-property fingerprints and refuses to repeat an unresolved rollback dispatch. Nullable configuration fingerprints remain nullable in new journals. No package, API, schema, security, app, or publication write path is present.

At that historical R4L stage, the runtime runner required package-backed guard steps and zero-row preflight before its distinct R4L one-shot Apply. That authorization is not reusable. Local static checks were `& .\tests\Phase3DR4LGuardCutover.Tests.ps1`; SDK marker/context checks were `dotnet run --project .\tests\CandidateCoreSdk\CandidateCoreSdk.Tests.csproj -c Release`.

## Consumed R4O write-context continuation

**Consumed outcome:** package updates 1; minimal CreateCandidate calls 1; automatic retries 0. The safe result was `UNSUPPORTED_CORE_WRITE_CONTEXT:CREATE_CANDIDATE:OTHER_PROTECTED_WRITE` during `CC_CREATE_CANDIDATE`, HTTP 400 / `0x80040265`. No deterministic exact pair was proven; `CANDIDATE_CORE_WRITE_CONTEXT_FAILURE_UNRESOLVED`. Final counts remain 0/0/0/0. Do not rerun the continuation mode or remove its lock/journal. No matrix or canary ran.

`R4OWriteContextApply` in [Test-BsoRsCandidateCoreRuntime.ps1](Test-BsoRsCandidateCoreRuntime.ps1) uses its own one-shot authorization, not either consumed historical runtime lock. It preserves trace-Off/no-Profiler/package-backed/zero-row gates, one minimal CreateCandidate, zero retries and the supported matrix only if creation succeeds. R4O unsupported-write diagnostics preserve closed action/write codes through service-stage wrapping. They do not prove ancestor registration passed; see the [source-derived matrix](../docs/PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

The diagnostic branch is conservatively capped at one existing-package update because the owner's attachment has conflicting one-/two-update wording. Do not reuse old journals, retry an unchanged build, or broaden the allowlist from a runtime label alone. No required CreateCandidate pair was statically missing.

## Earlier verified-ancestor acceptance authorization

**Consumed outcome:** one existing-package update, one failed CreateCandidate, zero retries, zero matrix actions; `CANDIDATE_CORE_TRUST_MODEL_FAILURE:UNSUPPORTED_CORE_WRITE_CONTEXT`. Final counts are 0/0/0/0. Do not rerun this mode or remove its lock/evidence. The reporting parser now preserves the generic unsupported-core-write category as well as trusted-parent predicates; this post-call local parser correction did not trigger a deployment or replay.

`VerifiedAncestorApply` in [Test-BsoRsCandidateCoreRuntime.ps1](Test-BsoRsCandidateCoreRuntime.ps1) selects a distinct owner-approved one-shot authorization and lock. It does not reopen historical R4M Apply. It requires trace logging Off, no active Candidate Core Profiler wrappers, the exact existing package-backed handler and all 50 package-backed guards, and zero initial rows. Its eight-call ceiling includes one minimal CreateCandidate, then the supported matrix only on success. Candidate autonumber/owner/actor/empty optional lookups, counts and creation Receipt are verified before proceeding.

The guard's server-owned registration model and matching-guard rollback requirement are defined in the [Security Model](../docs/SECURITY_MODEL.md). Registration reads run as the caller; missing read permission fails closed without granting privileges. Retained frozen deployment pins do not describe this new build and must not be silently bypassed or repurposed. The authorized package update uses its separately pinned artifact and new local durable one-shot evidence. See the latest [runtime report](../docs/PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md) for actual deployment/results. No safe existing live direct-write negative runner was found; do not improvise a successful-write canary.

## Historical R4M predicate-localization disposition

The owner-authorized fast-track diagnostic used a separately bounded session journal, not a replay of the consumed runtime Apply lock or frozen deployment pins. One existing package update returned HTTP 204; one minimal CreateCandidate returned the safe category `CANDIDATE_CREATE:TRUSTED_PARENT:MARKER_MISSING`. All earlier ancestor predicates passed. Post-counts remain 0/0/0/0, trace logging is Off, and there are no active Candidate Core Profiler wrappers. No deterministic propagation repair was proven, so no second build/update/call or matrix ran. Do not automatically rerun the diagnostic or open another backend phase.

[Test-BsoRsCandidateCoreRuntime.ps1](Test-BsoRsCandidateCoreRuntime.ps1) now preserves the closed trusted-parent predicate categories in sanitized failures. Its older Apply authorization remains consumed. [Deploy-BsoRsCandidatePluginPackage.ps1](Deploy-BsoRsCandidatePluginPackage.ps1) retains its historical artifact pins; they do not identify the newer diagnostic build. Do not bypass or silently replace those pins. Current artifact hashes, exact predicate order, validation and evidence limits are in the [runtime acceptance report](../docs/PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

## Historical Phase 3D-R4M trusted-parent correction

`CandidateCore/DataversePlugin.cs` now recognizes the private per-write marker on a bounded (eight-context) trusted `os_sr_cact` ancestor chain. It requires matching action category, stage, synchronous transaction, nested depth, caller identity, and exact mutation fingerprint; current-context values, caller `tag`, unrelated parents, malformed markers, and ancestors beyond the bound remain rejected. The marker is removed after each protected write and is not logged or persisted.

The unsigned existing package was validated without signing-key access. R4M local DLL/package/inventory pins are used by `Deploy-BsoRsCandidatePluginPackage.ps1` for package inspection. Owner direction permits bounded synthetic Candidate Core acceptance while organization auditing remains disabled; auditing is unchanged and is an external governance/release prerequisite before real candidate rollout. The existing `os_sr_cact_pkg` content was updated once and returned HTTP 204; package identity/version, package-backed handler/types, unchanged API contract, and all 50 package-backed guards reconciled exactly. Under the supported Dataverse package model, ordinary GET need not expose uploaded bytes and related PluginAssembly timestamp advancement is not required; exact deployed-byte equivalence remains unavailable, but this is not a package-update failure. The one R4M synthetic CreateCandidate call returned the exact R4L `CALLER_MARKER` failure; post-failure counts remained 0/0/0/0. Runtime classification: `PACKAGE_GUARD_PARENT_CONTEXT_FAILURE`; package disposition: `PACKAGE_UPDATE_ACCEPTED_CONTENT_NOT_BYTE_RECONCILABLE`. The package-update allowance and R4M runtime one-shot are consumed. Do not update the package or retry/invoke another API. Plug-in Profiler/context capture is the next diagnostic. No handler or guard-step PATCH is required by the approved R4M scope.

## VS Code Readiness

[Test-BsoVsCodeReadiness.ps1](Test-BsoVsCodeReadiness.ps1) performs local tool checks and read-only PAC environment/Solution checks. Its PAC app-authoring capability result is based on the `create` entry in successful `pac model help` output, not the literal phrase `model create`. Run the synthetic parser regression checks with `& ./tests/ReadinessChecks.Tests.ps1`; they do not invoke PAC or contact an environment.

The script separately reports MCP configuration presence, runtime config source, discovery, callability, permission scope, wildcard tool selection, environment-specific endpoint presence, and skill-lock path alignment. Configuration presence is not treated as proof of a working server; endpoint values are never printed. During Sprint 02B inspection, root `.mcp.json` declared two servers with wildcard tool selection and an environment-specific HTTP endpoint, while `.vscode/mcp.json` had an empty `servers` object. VS Code log records from 20-21 October 2026 reported that PAC MCP was unsupported by the installed CLI and Dataverse authorization-server metadata discovery returned 404. The current VS Code MCP runtime source is **UNKNOWN**; neither server was started or called in Sprint 02B. Both configuration files are preserved because the supported configuration source/installer contract could not be proven. Do not add endpoint values to tracked files or infer read-only tool permissions from configuration.

The `skills-lock.json` entries point to `.github/plugins/dataverse/skills`, which does not exist in this workspace. The corresponding nine skill files are under `.agents/skills`; five project skills are under `.github/skills`. No duplicate skill directory names were found across those roots. Whether the lockfile belongs to a separate plugin installer and whether Copilot discovers each local directory are **UNKNOWN**. The readiness check reports path mismatch but does not rewrite the lockfile or reinstall skills.

## Phase 3B.2 Status-History Choice Replacement

[Provision-BsoRsCandidateChildTables.ps1](Provision-BsoRsCandidateChildTables.ps1) includes `-ReplacementPreflightOnly`, a GET-only mode that checks the current manifest, target/request identity, Candidate Core metadata, zero History rows, and `RetrieveDependenciesForDelete` for exactly the two manifest-resolved History status attributes. It cannot dispatch metadata writes.

`-ReplaceStatusChoiceColumns` is a separately authorized destructive mode, not a fallback from in-place repair. It requires a new absolute `-ReplacementEvidencePath` JSON path in an existing directory and an explicit authorization reference. It allows at most DELETE Previous, POST Previous, DELETE New, POST New, preserving approved names/properties and binding to `os_sr_candstat`. It reserves each dispatch in the journal before sending, proves deletion absence and exact recreation with GET, and stops on rows, dependencies, failures, uncertain outcomes, or mismatches without resending. No PUT, table/Choice-definition write, business data, security/app change, or publication is allowed in this mode.

The 24 October owner authorization has been consumed successfully; **do not rerun it**. Existing journal reuse is rejected, and the required initial wrong-binding state no longer exists. Organization audit activation remains externally pending. See the [Phase 3B.2 report](../docs/PHASE_3B2_CANDIDATE_CHILD_TABLES_REPORT.md#34-owner-authorized-two-column-replacement) for actual results. Validate locally with `& .\tests\Phase3B2CandidateChildProvisioning.Tests.ps1` and `& .\tests\Phase3ACandidateCoreDesign.Tests.ps1`; neither suite contacts Dataverse.

## Reference Table Provisioning

[Provision-BsoRsTaTable.ps1](Provision-BsoRsTaTable.ps1) is the shared reference-table provisioner; its filename and default `os_sr_ta` selection remain for backward compatibility. [ReferenceTableDefinitions.psd1](ReferenceTableDefinitions.psd1) declares TA and three reference schemas. `-TableName` selects exactly one of `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, or `os_sr_loc`. The owner approved Phase 1D-D Apply and the three plural labels on 20 October 2026. The first Position Apply attempt returned HTTP 401 at the first metadata POST; its immediate read-only reconciliation found no Position metadata. A separate, single owner-authorized Sprint 02C recovery POST later had an unavailable status and an immediate GET reconciliation reported absent. Sprint 02C.1 then performed fresh GET-only reconciliation and verified the exact Position metadata and Solution membership. Do not retry, recreate, or run the recovery mode: Position now exists. Candidate Source and Location Apply were not attempted during that earlier Phase 1D-D activity; Candidate Source was later created in Sprint 02E and Location in Sprint 02F.3. See [Current State](../docs/CURRENT_STATE.md) for the latest evidence.

The default mode is online **DryRun** (interactive auth plus read-only preflight). `-PlanOnly` prints and locally validates the payload without authentication or network calls. Metadata POSTs are available only through `-Apply` or a specifically guarded bounded mode; each write mode requires typed confirmation. Never use Apply without separate explicit approval.

### Sprint 02D Bounded Modes

`-CreateOnlyCandidateSource` is restricted to `os_sr_csrc`. It verifies the exact PlanOnly payload fingerprint, requires Position to be verified published, requires the process-scoped `BSO_RS_EXPECTED_USER_ID` to match PAC, requires the expected `os_sr_ta`/`os_sr_pos` inventory and no unmapped Entity/Attribute Solution components, then permits at most one `POST EntityDefinitions` with the Solution header. It performs GET-only reconciliation, fixes `MaximumRetryCount` at zero, and never publishes automatically. Candidate Source publication, if separately proven necessary, uses `-PublishOnly -TableName os_sr_csrc`.

`-PublishOnly` is restricted to Position or Candidate Source and permits at most one table-scoped `POST PublishXml`. It requires a fresh preflight and a `RetrieveEntity` comparison showing either `PUBLISHED_WITH_UNPUBLISHED_DELTA` or `UNPUBLISHED_ONLY`; `PUBLISHED_NO_PENDING_DELTA` is left unchanged, and `UNKNOWN` blocks without a write. The mode requires only the effective publish privilege and cannot create or alter schema.

Publication detection uses Microsoft's [RetrieveEntity Web API function](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrieveentity?view=dataverse-latest) twice (`RetrieveAsIfPublished=false` and `true`) and compares normalized schema metadata. It does not infer publication from `solutioncomponents.componentstate`. The classifications are `PUBLISHED_NO_PENDING_DELTA`, `PUBLISHED_WITH_UNPUBLISHED_DELTA`, `UNPUBLISHED_ONLY`, and `UNKNOWN`; failed or malformed retrievals fail closed as `UNKNOWN`. `-VerifyPublicationOnly` is restricted to Position and Candidate Source and runs the comparison after read-only identity, Solution, Publisher, inventory, table, and membership checks. It permits GET only and sets `MaximumRetryCount` to zero. Bounded-create results include request counts; see [Current State](../docs/CURRENT_STATE.md) for Sprint 02E's one-time count-retention gap and observed outcome.

### Sprint 02F Controlled Location Mode

`-LocationPreflightOnly -TableName os_sr_loc -DisplayCollectionName Locations -AuthorizationReference <safe-reference>` runs the Location-specific environment, PAC/Az/WhoAmI identity, Solution/Publisher, reference-table schema/publication, project inventory, Location absence/component, and effective-privilege checks without entering the typed write-confirmation flow. It pins `BSO_RS_EXPECTED_USER_ID` to the PAC identity in process scope only after PAC, the existing Az user context, and Dataverse WhoAmI agree. Every required privilege must be returned by name at Global depth. Every Dataverse request is GET-only with `MaximumRetryCount=0`; the mode explicitly rejects non-GET methods, performs no writes, and redacts environment identifiers from its plan output. It returns `READY_FOR_LOCATION_EXECUTION` only when all gates and the safe authorization-reference format pass; an existing Location table returns `PARTIAL_STATE`, and any failed or unknown gate returns `BLOCKED`.

`-CreateOnlyLocation -TableName os_sr_loc -DisplayCollectionName Locations` is restricted to the Location reference table and its approved three payloads. It requires the expected-user process guard, PAC/Az/WhoAmI identity agreement, the approved VN LMV IT environment and unmanaged Solution/Publisher, the exact TA/Position/Candidate Source inventory, Location absence, mapped Solution components, and create privileges. It also requires a safe external authorization reference and typed confirmation.

The mode recomputes SHA-256 fingerprints before dispatch for the Location table payload, Room/Resource Email attribute, and Location Details attribute. It permits only this order: one `POST EntityDefinitions`, one Room/Resource Email attribute POST, then one Location Details attribute POST. Each write has `MaximumRetryCount=0`; each response is independently reconciled with GET-only metadata and Solution-membership reads carrying `Consistency: Strong`. A missing or partial read-back stops the sequence without retry. After the final column it verifies the full schema, inventory, Solution component mapping, unchanged audit settings, and published versus as-if-published metadata. It never calls `PublishXml`, PATCH, DELETE, or business-data endpoints.

Generic `-Apply` is disabled for Location so it cannot take the broader publish-after-create path. Strong consistency is applied only to bounded Location post-write metadata read-back and final verification requests. It does not alter HTTP response classification or authorize retries. `-PlanOnly -TableName os_sr_loc` remains offline and reports the three payload fingerprints.

Sprint 02F.3 completed this bounded path. Final GET-only reconciliation verified the table, both additional columns, Solution membership, exact project inventory, and `PUBLISHED_NO_PENDING_DELTA`; no publication or business-data write occurred. The recorded request counts and evidence are in [Current State](../docs/CURRENT_STATE.md).

### Interactive Authentication Prerequisites

Online mode follows Microsoft's [PowerShell Dataverse Web API quickstart](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/quick-start-ps): Az PowerShell interactive authentication, then `Get-AzAccessToken -ResourceUrl $OrganizationUrl -AsSecureString`. The script converts the SecureString to plaintext only in process memory for the HTTP Authorization header and never prints or persists it. It uses no custom MSAL assembly, app registration, PAC token cache, browser scraping, or `pac auth token`. PAC's documented token command was checked; its audience is `https://api.powerplatform.com`, so it is not a Dataverse token. `pac env who` remains read-only environment identity verification.

The official quickstart prerequisites are PowerShell 7.4 or later and Az PowerShell 11.1.0 or later. That Az version refers to the umbrella module, not Az.Accounts. The script imports Az.Accounts and checks for `Get-AzAccessToken -ResourceUrl -AsSecureString`, then requires a SecureString result. Local inspection confirmed PowerShell 7.6.7 and Az.Accounts 5.5.3 with those parameters available. Windows PowerShell 5.1 still supports offline `-PlanOnly` only. No dependency was installed by this verification. Review Microsoft's module source and organizational policy before installing or updating PowerShell/Az.

The script requires process-scoped `BSO_RS_ENVIRONMENT_NAME`, `BSO_RS_ORG_URL`, `BSO_RS_EXPECTED_ENVIRONMENT_ID`, and `BSO_RS_EXPECTED_ORG_ID`. It verifies the active `pac env who` identity and Dataverse `WhoAmI`; it does not switch environments. The signed-in user needs required metadata customization and Solution privileges; the script does not elevate roles. MFA and Conditional Access remain enforced.

Keep URLs, environment/organization IDs, credentials, and tokens outside this repository. Tokens exist only in process memory and are cleared by the script after execution.

### Offline Preview

```powershell
& (Join-Path $PWD 'scripts/Provision-BsoRsTaTable.ps1') -PlanOnly -EnvironmentName 'VN LMV IT' -OrganizationUrl '<approved-org-url>' -ExpectedEnvironmentId '<approved-environment-id>' -ExpectedOrganizationId '<approved-organization-id>'
```

The API requires `DisplayCollectionName`. The owner explicitly approved `TA Directories` for Phase 1D-C. Supply `-DisplayCollectionName 'TA Directories'` to show that explicit value in the preview; the script retains its explicit-input gate for Apply.

### Online DryRun

After installing the documented prerequisites through the approved IT process and setting the required process-scoped environment variables, run the authenticated read-only DryRun:

```powershell
& (Join-Path $PWD 'scripts/Provision-BsoRsTaTable.ps1')
```

The script validates PAC environment/organization/user identity, requires the same authorized user in the Az context, obtains a Dataverse-resource token as SecureString, and uses GET requests only. It verifies WhoAmI, Publisher, Solution, audit baseline, project inventory, and the local payload. Every existing reference table must match its declaration and have valid Solution membership; unexpected project tables fail closed. Existing-table snapshots and audit settings are compared before/after the run. DryRun can verify an existing selected table; Apply always rejects an existing target. Treat displayed environment URL and IDs as sensitive operational configuration; do not save output in this repository.

Historical Phase 1D-C and Phase 1D-D read-only checks passed using PowerShell 7.6.7 and Az.Accounts 5.5.3. On 20 October 2026, the approved Position Apply reached one `POST EntityDefinitions` attempt and returned `401 Unauthorized`; immediate reconciliation found Position absent. A separately authorized Sprint 02C recovery later dispatched one POST; its sanitized summary retained no HTTP status, error code, or request/correlation IDs and immediate reconciliation reported absent. The 02C.1 live read now verifies exact Position metadata and Solution membership. No further retry, deletion, recreation, or other-table Apply occurred in 02C.1. Read-only effective-privilege checks for the earlier run returned Global depth for `prvCreateEntity`, `prvCreateAttribute`, `prvCreateCustomization`, and `prvPublishCustomization`. **The original 401 root cause and the Sprint 02C response details remain unavailable; do not reconstruct them.**

The successful TA flow and failed Position flow used the same token-before-preflight / typed-prompt / POST ordering, bearer Authorization construction, JSON Content-Type, `If-None-Match`, and `MSCRM.SolutionUniqueName` header. Transcript timing puts the first confirmation and returned failure within seconds; the historical token expiry is unavailable, so expiry cannot be conclusively ruled in or out. The helper validates Dataverse audience/tenant/scope/expiry and refreshes through Az.Accounts before a request when under five minutes remain, including after confirmation. Sprint 02C.1 additionally preserves safe diagnostics on HTTP exceptions: status (or explicit `UNKNOWN`), error classification, allowlisted error code and challenge properties, validated request/correlation GUIDs, relative path, exception category, and dispatch/write Booleans. It never serializes a token, full headers, or raw response body. These changes cannot recover prior response details or prove the original 401 cause. See [Current State](../docs/CURRENT_STATE.md). Do not retry or bypass policy.

### Controlled Position Recovery (Single Authorized Attempt Already Used)

Sprint 02B.1 added an explicit `-CreateOnlyRecovery` mode for `os_sr_pos`. It was invoked once under Sprint 02C owner authorization and must not be run again: Sprint 02C.1 now verifies Position exists exactly and belongs to the project Solution. The original one-attempt authorization is consumed and does not authorize another write. The remaining procedure below records the safeguards used for that attempt; it is not an executable recommendation. No step permits switching environments, identities, authentication mechanisms, or APIs to work around a failure.

**Preconditions**

1. The project owner and the responsible VN LMV IT environment/Dataverse administrator approve one controlled recovery attempt in writing, including the Production-class development target and the exact `os_sr_pos` operation. If the failure requires a privilege or policy change, stop for its own formal security approval; this procedure does not authorize such a change.
2. Set the existing process-scoped environment values for VN LMV IT and `BSO_RS_EXPECTED_USER_ID` to administrator-verified values. The mode checks PAC against the expected environment/organization and user IDs, and checks the existing Az user against PAC without emitting the identity. It will not trigger `Connect-AzAccount`, switch profiles, change identity, or print the configured URL/IDs.
3. Read-only preflight independently confirms `os_sr_pos` is absent from `EntityDefinitions`, the current project inventory is exactly `os_sr_ta`, and every Entity/Attribute component in the project Solution maps to currently verified project metadata. Any unidentifiable Entity or Attribute component blocks recovery. Reconfirm the `os_bso_rs_support` Publisher (`os` prefix), unmanaged `os_sr_bso_rs_support` Solution, and effective `prvCreateEntity`, `prvCreateAttribute`, and `prvCreateCustomization` privileges. `prvPublishCustomization` is not required because this mode cannot publish.
4. The mode recalculates the PlanOnly table payload SHA-256 before authentication and compares it to the approved fingerprint below. It blocks before authentication if the hash differs. It also validates the exact declared Position schema; no additional columns, keys, relationships, audit flags, or data rows are planned.
5. Invoke only the dedicated mode, never `-Apply`:

   ```powershell
   & ./scripts/Provision-BsoRsTaTable.ps1 -CreateOnlyRecovery -TableName os_sr_pos -DisplayCollectionName 'Positions' -AuthorizationReference '<approved-change-reference>'
   ```

   The reference must identify a separately approved operational authorization and match the mode's restricted safe-character syntax. The script then requires the exact typed phrase `RECOVER CREATE os_sr_pos IN VN LMV IT AUTHORIZATION <approved-change-reference>`. Neither a reference string nor typed confirmation proves external approval; the project owner and environment administrator must confirm that approval independently. The existing `-Apply` sequence remains unchanged and is **not suitable** for this one-POST recovery because it posts additional attributes and calls table-scoped `PublishXml`.

**Single intended request**

- Method and target: one `POST` to the configured, verified organization's `/api/data/v9.2/EntityDefinitions` endpoint. Do not substitute MCP `create_table`, PAC, another endpoint, or another identity.
- Body: the exact PlanOnly-validated `Microsoft.Dynamics.CRM.EntityMetadata` payload for `os_sr_pos`, including only the approved table metadata and primary-name attribute.
- Authentication: the existing Az.Accounts user token requested for the configured Dataverse organization resource. The same user must match PAC. Validate tenant, audience, delegated `user_impersonation` scope, and expiry in memory; never output or persist the token or raw claims.
- Headers: bearer credential header (never logged), JSON content type, Accept JSON, OData 4.0 version headers, `If-None-Match: null`, and `MSCRM.SolutionUniqueName: os_sr_bso_rs_support`. Require HTTPS, the verified organization API origin, and redirects disabled.
- Privileges: recovery preflight requests the effective `prvCreateEntity`, `prvCreateAttribute`, and `prvCreateCustomization` set for the existing PAC/Az identity. Missing or unavailable privilege evidence blocks the write. No privilege is granted or changed. `prvPublishCustomization` is deliberately not checked because publishing is prohibited.
- Response: treat only a 2xx response as transport success, not proof of a complete deployment. The exact historical response code and body are unavailable. Independently read back the table and Solution membership before any next operation.

**Sanitized evidence to retain for this one attempt**

The local mode emits the UTC attempt timestamp; environment and identity match Booleans; verified privilege names; state and state-transition timestamps; expected/actual payload hashes; response class/status; allowlisted Dataverse error code and safe summary; validated request/correlation GUIDs; reconciliation result; and whether a write may have occurred. Authentication tenant/audience/scope/expiry are validated in memory by the existing token helper and are not emitted as claims. Never retain Authorization or other full headers, raw token/claims, full response body, credentials, user email, or unfiltered exception text.

**Stop, outcome handling, and reconciliation**

- **401:** stop all writes and reconcile by GET only. Preserve sanitized diagnostics. Have the authorized administrator investigate identity membership, Conditional Access, token audience/scope/expiry, and the challenge using approved logs. Do not refresh into a different identity, switch auth surface, or retry.
- **403:** stop all writes and reconcile by GET only. Request an administrator review of effective privileges and policy; do not self-elevate or retry after a privilege change without a separately approved plan.
- **Deterministic request/schema 4xx other than 408/429:** stop and inspect the sanitized error. Do not assume the metadata write did not occur; reconcile by GET before any recovery decision.
- **408, 429, 5xx, transport error, or timeout:** treat the write outcome as uncertain. Do not automatically retry. Reconcile table metadata and Solution membership using GET-only reads, including whether the table, primary column, or Solution component partially exists.
- **Any 2xx:** issue no subsequent write until independent read-back verifies the exact table schema, generated primary ID/name, absence of unintended metadata, and project Solution root membership. Only a separate authorization may proceed to the next table.
- **Partial or uncertain state:** the provisioner intentionally has no resume, delete, recreate, or automatic repair route. Preserve observed state and prepare a separately reviewed recovery plan. Do not delete or recreate the table; its name and ownership are durable creation-time decisions.

The later `os_sr_csrc` and `os_sr_loc` tasks are independent schemas but remain serialized behind Position recovery by the approved runbook sequence. They require their own fresh preflight and explicit authorization; neither is implicitly authorized by a successful Position recovery. See [Current State](../docs/CURRENT_STATE.md) and [Phase 1D-B Reference Table Runbook](../docs/PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md).

#### One-Attempt State Machine (Implemented Locally)

```text
PRECHECK --all local/external gates and exact payload hash pass--> READY
PRECHECK --any mismatch/unknown required fact/approval missing--> BLOCKED
PRECHECK --payload fingerprint mismatch--> FAILED_VALIDATION
READY --one guarded POST EntityDefinitions--> WRITE_ATTEMPTED
WRITE_ATTEMPTED --any response/transport result--> RECONCILING (GET only)
RECONCILING --exact schema and Solution membership--> VERIFIED_SUCCESS
RECONCILING --unexpected/partial metadata--> PARTIAL_STATE
RECONCILING --401 with no exact table--> FAILED_AUTH
RECONCILING --403 with no exact table--> FAILED_AUTHZ
RECONCILING --deterministic request/schema 4xx with no exact table--> FAILED_VALIDATION
RECONCILING --429/408/5xx/timeout/transport ambiguity or unknown read-back--> UNCERTAIN
```

All outcomes after WRITE_ATTEMPTED permit only GET reconciliation. `Invoke-RestMethod -MaximumRetryCount 0` is set for every request in this mode; the write guard also rejects every second POST and every path except `EntityDefinitions`. PATCH/DELETE are unsupported by the request wrapper. The recovery branch returns before the normal Apply continuation, so it cannot post additional attributes or call PublishXml. Terminal states cannot authorize another write. Any partial/unexpected metadata takes precedence; exact metadata and Solution membership are required for VERIFIED_SUCCESS. Do not publish, delete, recreate, compensate, or change roles/privileges. Local tests use mocked transport only; **remote execution remains unauthorized**.

#### Sanitized Evidence Record (Template)

Keep any operational record outside the repository unless organizational policy approves a sanitized incident artifact. Use null/omitted values when an item was not returned; never infer evidence. The local mode's diagnostic is not an approval record.

| Record area | Allowlisted fields |
|---|---|
| Preflight | `attemptTimestampUtc`; `environmentName` (`VN LMV IT`); `environmentMatch` Boolean; `identityMatch` Boolean (expected ID/PAC/Az same user; no user identifier); `solutionUniqueName`; `solutionType` (`unmanaged`); `publisherUniqueName`; `publisherPrefix`; `targetTableAbsent` Boolean; `solutionComponentAbsent` Boolean; effective privilege results; `payloadSha256`. |
| Request/response | `method` (`POST`); relative `path` (`/api/data/v9.2/EntityDefinitions`); `httpStatus`; allowlisted sanitized Dataverse error code/message; valid request/correlation GUIDs only; selected safe challenge properties only; `tokenAudienceValid`, `tokenScopeValid`, `tokenExpiryValid` Booleans; `writesMayHaveOccurred` Boolean. |
| Reconciliation | `reconciliationTimestampUtc`; GET-only results for target table and metadata, exact expected attributes, keys, relationships, and project Solution root; `outcome` (`VERIFIED_SUCCESS`, `FAILED_AUTH`, `FAILED_AUTHZ`, `FAILED_VALIDATION`, `UNCERTAIN`, or `PARTIAL_STATE`); concise sanitized notes. |

Never include access/refresh tokens, Authorization or other full headers, JWT claims, user email, tenant ID, full organization URL, credentials, full response body, candidate data, or unfiltered exception text. The emitted diagnostic includes redacted verification booleans and the Position fingerprint; it does not prove external authorization or emit raw identity/token claims. The historical incident was not captured with these fields.

#### Position Payload Identity

The offline Position PlanOnly payload was serialized from `TablePayload` using `ConvertTo-Json -Depth 40 -Compress`, encoded as UTF-8 without a BOM, and hashed with SHA-256. Fingerprint: **`0f7372eeb66c0214ae08ed0dc74f82c981cc4cd73baa9156f16d6e1bd1f48e80`**. The synthetic provisioning test recalculates and asserts this value. It fingerprints the table-create payload (table plus primary-name attribute), not future requests, environment identity, or the entire Apply sequence. Recalculate after any payload/script change; a mismatch blocks use of the recorded approval until reviewed.

#### Exact GET-Only Reconciliation

After the single authorized POST—or any uncertain result—use only the existing verified Dataverse organization and the existing authenticated identity. Do not follow untrusted continuation URLs. Inspect:

1. `GET EntityDefinitions(LogicalName='os_sr_pos')` for exact logical/schema name, metadata ID, `OrganizationOwned`, display `Position`, plural `Positions`, `PrimaryIdAttribute`, and `PrimaryNameAttribute`.
2. `GET EntityDefinitions(LogicalName='os_sr_pos')/Attributes` and compare custom attributes with exactly one declared custom attribute: primary `os_sr_pos_ttl`, String/Text, length 200, `ApplicationRequired`, `IsPrimaryName=true`. Confirm the generated primary GUID attribute exists and is the PrimaryIdAttribute; ignore standard platform attributes only after classifying them as noncustom. Any other custom attribute means `PARTIAL_STATE`.
3. `GET EntityDefinitions(LogicalName='os_sr_pos')/Keys` and all three relationship collections (`ManyToOneRelationships`, `OneToManyRelationships`, `ManyToManyRelationships`); expect no custom keys or relationships. Any unexpected custom metadata means `PARTIAL_STATE`.
4. Query `solutioncomponents` read-only for the project Solution ID and the table MetadataId, component type Entity (`1`). Verify a Solution root component and `rootcomponentbehavior=0` (includes subcomponents), or the exact explicitly supported membership representation. No membership or conflicting membership blocks `VERIFIED_SUCCESS`.
5. Reconfirm the project Solution identity and retrieve the selected table metadata a second time if the first read is inconsistent. Reads do not authorize writes.

The table and names are durable creation-time metadata: there is no automatic rollback. Leave partial or unpublished metadata untouched pending a separate admin-reviewed recovery plan. Do not run `PublishXml` as part of this one-POST attempt.

### Declarative Payloads and Approval Boundary

All tables use `Microsoft.Dynamics.CRM.EntityMetadata`, `OrganizationOwned`, `IsActivity=false`, `HasActivities=false`, and `HasNotes=false`. The primary name alone is embedded in `Attributes` during table creation. Additional columns have individual metadata POSTs only during separately authorized Apply. No keys, relationship definitions, data rows, or audit properties are supplied.

| Table / display label | Plural / approval | Primary name: schema, label, type, limit, requiredness | Additional columns |
|---|---|---|---|
| `os_sr_pos` / Position | Positions / approved | `os_sr_pos_ttl`, Position Title, String/Text(200), ApplicationRequired, primary | None |
| `os_sr_csrc` / Candidate Source | Candidate Sources / approved | `os_sr_csrc_nm`, Source Name, String/Text(100), ApplicationRequired, primary | None |
| `os_sr_loc` / Location | Locations / approved | `os_sr_loc_nm`, Location Name, String/Text(150), ApplicationRequired, primary | `os_sr_loc_rmeml`, **Room/Resource Email**, String/Email(254), None; `os_sr_loc_det`, Location Details, Memo/Text(1000), None |

The request proposed **Room Resource Email**, but the authoritative [schema](../docs/DATAVERSE_SCHEMA_SPECIFICATION.md) and [runbook](../docs/PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md) use **Room/Resource Email**; the definition retains that exact label. The email's conditional booking requirement is not create-time metadata requiredness. Location Details uses `MemoAttributeMetadata`, `AttributeTypeName=MemoType`, and `Format=Text`; String fields use `StringAttributeMetadata` and `FormatName.Value`. Expected primary GUIDs are `os_sr_posid`, `os_sr_csrcid`, and `os_sr_locid`.

Generate the complete exact JSON payloads locally, without authentication:

```powershell
& ./scripts/Provision-BsoRsTaTable.ps1 -TableName os_sr_pos -PlanOnly
& ./scripts/Provision-BsoRsTaTable.ps1 -TableName os_sr_csrc -PlanOnly
& ./scripts/Provision-BsoRsTaTable.ps1 -TableName os_sr_loc -PlanOnly
```

For authenticated DryRun, omit `-PlanOnly` and leave `-Apply` absent, with the required process-scoped environment values set. Results are JSON on stdout with stage/status, inventory and verification flags, and GET/POST attempt counts. Tokens are never included. Do not persist live environment configuration or raw authentication output in the repository.

The same code owns authentication, PAC/WhoAmI preflight, Publisher/Solution verification, typed String/Memo read-back, and Solution membership verification. Root behavior `0` includes subcomponents; otherwise every declared column must have explicit membership. It checks exact names/labels/types/lengths/requiredness, primary name/GUID, state/status, keys, custom columns/relationships, and existing-table snapshots. GET requests are restricted to metadata/configuration; continuation links must remain on the same HTTPS API origin and redirects are disabled. The transport rejects POST outside confirmed Apply and restricts metadata creates and publication to the single selected table. There are no retry, deletion, recreation, or business-row paths. An uncertain write emits stopped/reconciliation status and must not be retried automatically.

**Apply commands are owner-approved but currently blocked after the Position 401. Do not execute these commands until the authorization failure and uncertain-write incident are resolved and a controlled recovery/retry is explicitly authorized.** The approval itself covers only these exact targets; typed confirmation remains mandatory:

```powershell
& ./scripts/Provision-BsoRsTaTable.ps1 -TableName os_sr_pos -Apply -DisplayCollectionName 'Positions'
& ./scripts/Provision-BsoRsTaTable.ps1 -TableName os_sr_csrc -Apply -DisplayCollectionName 'Candidate Sources'
& ./scripts/Provision-BsoRsTaTable.ps1 -TableName os_sr_loc -Apply -DisplayCollectionName 'Locations'
```

Execute one approved table at a time and verify it before considering another. Explicit label input does not itself grant approval. Apply requires the exact phrase `CREATE <logical-name> IN VN LMV IT WITH COLLECTION <plural>`. Never execute these commands merely to test the path.

Run the dependency-free synthetic suite in PowerShell 7.4+:

```powershell
& ./tests/ReferenceTableProvisioning.Tests.ps1
```

The plain assertion harness is run directly, not through VS Code test discovery. It covers exact four-table payloads, TA regression fixtures, metadata drift rejection, membership positive/negative cases, no-write and no-business-read guards, and same-origin/foreign OData pagination using mocked transport. Apply entry points and real HTTP requests are never invoked by the suite.

### Troubleshooting

- **PowerShell version too old:** use PowerShell 7.4 or later. The current Windows PowerShell 5.1 shell supports `-PlanOnly` only.
- **Az.Accounts missing or incompatible:** verify `Get-AzAccessToken` supports `-ResourceUrl` and `-AsSecureString`. Do not confuse the Az umbrella version with the Az.Accounts version. Installation or updates require IT review; the script does not install modules.
- **Interactive sign-in blocked by policy:** stop and provide IT the exact Az/Entra error; do not use cached PAC tokens, browser scraping, or another authentication route to bypass policy.
- **User is not a member of the organization / 401 or 403:** verify the selected account is a member of VN LMV IT and has approved Dataverse metadata and Solution privileges.
- **Environment mismatch:** verify the selected PAC environment and the process-scoped name, URL, environment ID, and organization ID. The script never switches environments.
- **DNS/host failure:** verify the supplied organization URL is the approved Dataverse URL and the network can resolve/reach it.
- **PAC token audience:** `pac auth token` targets `https://api.powerplatform.com`; never use it with the Dataverse URL.
- **Invalid header value `null`:** PowerShell 7 validates `If-None-Match` syntax locally. The request uses `SkipHeaderValidation` for Dataverse's `If-None-Match: null` header; HTTPS and verified-organization URL checks remain enforced.
- **HTTP 501 for metadata `startswith`:** Dataverse does not support that function on metadata entities. The script retrieves table logical names only and applies the project-prefix filter locally, preserving continuation-page handling.

### Apply Command (Executed Once; Do Not Repeat)

The owner approved exactly `os_sr_ta` and the plural label on 19 October 2026. The following invocation pattern was executed once with explicit verified target parameters; it is historical reference, not an instruction to rerun:

```powershell
& (Join-Path $PWD 'scripts/Provision-BsoRsTaTable.ps1') -Apply -DisplayCollectionName 'TA Directories'
```

Apply requires typing `CREATE os_sr_ta IN VN LMV IT WITH COLLECTION TA Directories`. The approved run created the table/primary name and TA Email and published only that table. It exited with `Solution membership verification failed` because it incorrectly required a separate attribute-component row. Independent GETs confirmed exact schema and whole-table inclusion through `rootcomponentbehavior=0` (**Include Subcomponents**). The local verifier now accepts this documented inclusion, or explicit membership of both approved columns when subcomponents are not included. Read-only verification passed; no write retry or membership repair occurred. Audit settings remained unchanged and only `os_sr_ta` exists in the project namespace.

Read-back queries cast string columns to `Microsoft.Dynamics.CRM.StringAttributeMetadata` for format/length checks. The generated GUID is verified as a primary ID without assuming its `IsCustomAttribute` flag. See Microsoft's [Solution Component reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/solutioncomponent#rootcomponentbehavior) for root inclusion semantics. Future runs against an existing project table intentionally stop at preflight; any repair needs a separately approved recovery scope.

See [Phase 1D-B runbook](../docs/PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md), [Dataverse Schema Specification](../docs/DATAVERSE_SCHEMA_SPECIFICATION.md), and [ALM and Deployment](../docs/ALM_DEPLOYMENT.md).

## Historical Phase 2D Adopted App Composition Plan

[Configure-BsoRsModelDrivenApp.ps1](Configure-BsoRsModelDrivenApp.ps1) targets only the adopted `srapp` AppModule. No switches means **PlanOnly**: local payload preview with no authentication, PAC call, or network request. `-DryRun` verifies PAC/Az identity, AppModule/Solution/Site Map/table/form/view metadata, the Solution `AppModuleSiteMap` binding, live AddAppComponents OData metadata, and Solution-export form/view membership using GETs and a temporary export ZIP that is deleted in `finally`.

The maximum sequence is two independent requests: PATCH only `sitemapxml` on the existing Site Map, then POST AddAppComponents for the existing TA table, Main form, and public view. The Site Map is not re-added because the Solution export already binds unique name `srapp`. The script does not call PublishXml/PublishAllXml, change role/audit records, delete components, or read business rows. Each write is followed by independent GET read-back; no retry, transaction, or rollback is assumed. If a write is ambiguous or read-back fails, stop and reconcile.

Only a separately approved future Apply may use `-Apply`, the exact confirmation phrase, a nonempty authorization reference, and the process-scoped identity values below. **Do not execute Apply under Phase 2D-P.**

```powershell
& ./scripts/Configure-BsoRsModelDrivenApp.ps1
& ./scripts/Configure-BsoRsModelDrivenApp.ps1 -DryRun
```

DryRun requires `BSO_RS_ENVIRONMENT_NAME`, `BSO_RS_ORG_URL`, `BSO_RS_EXPECTED_ENVIRONMENT_ID`, and `BSO_RS_EXPECTED_ORG_ID` in the current process; never save their values in the repository. Runtime AddAppComponents acceptance on this unpublished app and whether Site Map PATCH creates the expected unpublished layer remain unverified. See the [Phase 2D runbook](../docs/MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md).

## Historical Phase 2D Composition Plan (Superseded)

[Configure-BsoRsModelDrivenApp.ps1](Configure-BsoRsModelDrivenApp.ps1) targets only the owner-adopted AppModule `srapp`. Running it with no switches is **PlanOnly**: it prints the planned operations and typed `AddAppComponents` payloads without authentication, PAC, or network calls. `-DryRun` performs PAC identity checks and GET-only verification of the AppModule, Solution, Site Map, TA table/form/view, AppModuleSiteMaps export binding, and live OData action/component metadata. It also exports the target Solution to a temporary ZIP and deletes it in `finally`.

This original sequence (PATCH before POST) is historical and superseded by the Phase 2D.3 dedicated flow below. It must not be used for the current task.

Run PlanOnly and GET-only DryRun:

```powershell
& ./scripts/Configure-BsoRsModelDrivenApp.ps1
& ./scripts/Configure-BsoRsModelDrivenApp.ps1 -DryRun
```

DryRun requires `BSO_RS_ENVIRONMENT_NAME`, `BSO_RS_ORG_URL`, `BSO_RS_EXPECTED_ENVIRONMENT_ID`, and `BSO_RS_EXPECTED_ORG_ID` in the current process. Do not persist their values in the repository. Runtime acceptance of the AddAppComponents action on this unpublished app and the Site Map PATCH's draft-layer behavior remain unverified; see the [Phase 2D Runbook](../docs/MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md).

## Historical Phase 2D.1 srapp Composition — Blocked Before Write

The owner-authorized Phase 2D.1 preflight targets only the adopted `srapp` and the four approved reference-table experiences: TA, Position, Candidate Source, and Location. PlanOnly is local and makes no network calls. DryRun performs identity and GET-only app, Solution, Site Map, table/form/view, dependency, and validation checks.

Fresh live `ValidateApp` returned the blocking error **`App does not contain Site Map`**, despite the Solution export's package-level `AppModuleSiteMap.SiteMapUniqueName=srapp` binding. The proposed AddAppComponents list contains the 12 table/form/view components and excludes the existing Site Map. The scope decision to include the Site Map or use another supported association route remains open. **Do not use Apply until that decision and any changed write scope are explicitly authorized and a fresh preflight passes.** The app remains unpublished; no Site Map PATCH, AddAppComponents action, publish, role change, or retry occurred.

The recorded Phase 2D.1 total is 83 Dataverse GETs, zero Site Map PATCHes, zero app-component operations, zero PublishXml, zero publish operations, zero role changes, and zero retries. The final guarded DryRun made 25 GETs in addition to its separate identity WhoAmI GET; the total also includes earlier GET-only diagnostics. See the [Phase 2D.1 runbook](../docs/MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md) and [current state](../docs/CURRENT_STATE.md).

## Phase 2D.2 srapp Site Map Association — Verified

The separate `-SiteMapAssociationOnly` mode supports only `-DryRun` or `-Apply`; Apply requires the phase-specific confirmation phrase and authorization reference. It reruns the target identity and metadata preflight, requires exactly one existing Solution Site Map root and the exact `ValidateApp` blocker, then sends a single `AddAppComponents` payload containing only the live-verified existing `sitemapid`. It does not PATCH Site Map XML, add table/form/view components, publish, change roles, retry, or create/delete anything. The expected-user guard is pinned in process scope only after PAC, Az token context, and Dataverse WhoAmI identities agree. Post-write GET reconciliation checks the app identity/state, one direct Site Map component, no other components, unchanged Site Map XML and role associations, and cleared Site Map validation error.

Phase 2D.2 completed as **VERIFIED_SITEMAP_ASSOCIATED**: the one AddAppComponents POST returned HTTP 204. Recorded Dataverse Web API totals across the dry-run and Apply were 75 GET, 1 AddAppComponents POST, 0 other POST, 0 Site Map PATCH, 0 PublishXml, 0 publish, 0 role changes, and 0 retries. See the [Model-driven App Automation Runbook](../docs/MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md). The owner later separately authorized Phase 2D.3.

## Phase 2D.3 Reference UI Composition — Authorized, Preflight Blocked

`-ReferenceUiCompositionOnly` is the dedicated PlanOnly/DryRun/Apply mode for the four approved reference-table UI sets. DryRun requires the process-scoped VN LMV IT target variables and an already configured `BSO_RS_EXPECTED_USER_ID`; it never pins that guard from PAC. It freshly resolves only `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc`, requiring the exact Information Main form and named public active view for each, and validates Solution membership, the adopted `srapp`, the unique existing Site Map, and the two existing app roles.

Apply requires the exact confirmation phrase `APPLY PHASE 2D.3 IN VN LMV IT` and a nonempty authorization reference. It allows one AddAppComponents POST with exactly 12 table/form/view records; only after GET reconciliation and successful intermediate `ValidateApp` may it issue one `If-Match` Site Map PATCH. It then performs GET-only final reconciliation and validation. It has no publish, role, schema, or retry route. If any check fails after a write, it stops and requires manual reconciliation; do not rerun automatically.

The latest fresh Phase 2D.3 preflight stopped before Dataverse Web API access because the process-scoped target variables and expected-user guard were unavailable in all checked Windows environment scopes. **No live Dataverse GET or write occurred; outcome is BLOCKED_BEFORE_WRITE.** Restore configuration from the approved secure source, do not copy expected values from PAC, and run a new DryRun before Apply.

```powershell
& ./scripts/Configure-BsoRsModelDrivenApp.ps1 -PlanOnly -ReferenceUiCompositionOnly
& ./scripts/Configure-BsoRsModelDrivenApp.ps1 -DryRun -ReferenceUiCompositionOnly
```
