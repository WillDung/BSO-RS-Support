# Phase 3D - Candidate Core Synthetic Runtime Acceptance

Date: 25 October 2026. This report records the latest Phase 3D-R4D existing-package cutover/runtime result and retains earlier assessments as history. Source: owner authorization, current repository contract/source, live guarded metadata reconciliation, local offline validation, and Microsoft's published Dataverse metadata documentation.

## Latest Phase 3D-R4D Existing-Package Cutover and Runtime Result

**`PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK` — cutover reconciled; CreateCandidate failed at runtime; the exact legacy handler was restored.** Owner authorization permitted the handler-only cutover and at most one synthetic Candidate after exact reconciliation. Fresh R4D read-only evidence found the existing package, its File Store assembly, and both exact package-backed types. This supersedes the R4B `PLUGIN_PACKAGE_PROCESSING_FAILED` disposition for package-processing status: the package `content` field still returns no fingerprintable value, but PRT processing evidence plus the PackageId-linked assembly and exact types establish processing. No package upload, update, or deletion was performed.

### Fresh package/API/storage reconciliation

| Check | Fresh pre-cutover R4D read-only result |
|---|---|
| PluginPackage `os_sr_cact_pkg` | One exact row; ID `43765041-4fd0-f111-a05a-002248a1ba20` |
| Package-backed assembly `os_sr_cact` | ID `d71c6048-4fd0-f111-a05a-002248a1ba20`; linked by PackageId; SourceType `File Store` |
| Package handler type | `os_sr_cact.ApplyCandidateAction`; ID `d81c6048-4fd0-f111-a05a-002248a1ba20` |
| Package guard type | `os_sr_cact.ProtectCandidateCore`; ID `d91c6048-4fd0-f111-a05a-002248a1ba20` |
| Retained legacy assembly | ID `ebabddad-3635-471b-9e97-88dbb0396df0`; unchanged |
| Legacy handler / guard types | `ApplyCandidateAction` ID `b3ec49b1-be4c-4fb6-af10-3bac7a30e407`; `ProtectCandidateCore` ID `7a31c1da-5a8e-4488-b91e-cb5ae01cb77e` |
| Candidate Core Custom API `os_sr_cact` | ID `0745a0bf-4c77-4e64-8125-12bfbf439229`; bound to the legacy handler before cutover |
| API contract / privilege / Solution | Exact and unchanged; package and assemblies remain in the approved Solution |
| Candidate Core storage / receipt key | Exact; Operation Receipt alternate key Active |
| Business/evidence row counts | Candidate 0; Call Log 0; Status History 0; Operation Receipt 0 |

The live-derived one-to-one handler map and final disposition are:

| Custom API | Current legacy handler | Package-backed replacement |
|---|---|---|
| `os_sr_cact` (`0745a0bf-4c77-4e64-8125-12bfbf439229`) | `os_sr_cact.ApplyCandidateAction` (`b3ec49b1-be4c-4fb6-af10-3bac7a30e407`) | `os_sr_cact.ApplyCandidateAction` (`d81c6048-4fd0-f111-a05a-002248a1ba20`); now restored to the legacy handler |

The retained legacy guard `os_sr_cact.ProtectCandidateCore` remains `7a31c1da-5a8e-4488-b91e-cb5ae01cb77e`; its package-backed exact-typename counterpart is `d91c6048-4fd0-f111-a05a-002248a1ba20`. The exact rollback mapping is retained in the short-lived R4D execution journal as well as recorded here. No type-to-API mapping was inferred from naming; the live API and PlugInType reads establish the relationship. Plug-in types are included with their containing assembly Solution component; no standalone type Solution-component rows are claimed.

### Local continuation path and stop boundary

The deployment runner now has separate `CutoverExistingPreflight`, `CutoverExistingApply`, and `RollbackExistingCutover` paths. Apply repeats identity, Solution, Candidate Core/receipt-key, API contract, package/type/legacy topology, and zero-row gates; writes a new one-shot rollback journal before dispatch; PATCHes only the existing Custom API `PluginTypeId` relationship; uses automatic retries `0`; and immediately GET-reconciles. It does not POST or update the package. Rollback requires a determinately classified R4D runtime defect, uses only the retained legacy handler ID, is limited to one PATCH, and preserves the package and both assemblies.

The one authorized cutover PATCH returned HTTP 204 and immediately reconciled to the package handler. The R4D runtime-specific preflight then returned ready with zero Candidate, Call Log, Status History, and Receipt rows. The runtime runner dispatched CreateCandidate exactly once using the synthetic `[SYNTHETIC-E2E] Candidate Core Acceptance` name and a reserved `.invalid` email, omitting optional `CandidateId` and `ExpectedStatus`. Dataverse rejected the request with HTTP 400, code `0x80040265`, `INVALID_EXPECTED_STATUS`. The call was a determinate rejection (`REJECTED`), not an uncertain write; no automatic retry or second API invocation occurred. A fresh count-only check after rejection again found all four business/evidence counts at zero. No synthetic Candidate or evidence rows were retained.

Primary runtime failure classification: `CREATECANDIDATE_RUNTIME_FAILURE`. The rest of the runtime matrix was not run. The approved one-PATCH rollback returned HTTP 204 and immediately/full-reconciled the Custom API to legacy `os_sr_cact.ApplyCandidateAction` (`b3ec49b1-be4c-4fb6-af10-3bac7a30e407`). The package-backed assembly/types and legacy assembly/types remain present. The final status is `PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK`, with runtime failure classification `CREATECANDIDATE_RUNTIME_FAILURE`; the implementation cause is not yet established. The optional `ExpectedStatus` rejection is an open contract/runtime discrepancy, not a verified root cause. Do not retry the API, re-cut over, update the package, or repair the operation without new authorization and a bounded diagnosis.

R4D action counts: existing package upload/update 0; handler cutover PATCH 1; rollback PATCH 1; Candidate Core Custom API dispatch 1 (rejected); business/evidence rows 0; automatic retries 0; schema, Choice, security, app, organization-audit, or publication writes 0; commit/push 0. The cutover preflight used 130 GETs; cutover apply 203 GETs; runtime preflight 14 GETs; runtime apply 14 GETs; post-failure count/preflight 14 GETs; rollback 194 GETs.

Final offline validation: all 10 PowerShell suites passed (1,099 assertions); the Candidate Core operation harness passed (79 assertions); all 20 PowerShell files parsed; 84 relative links in the modified documents resolved; the added-line privacy scan and `git diff --check` passed. These checks do not constitute live runtime acceptance. See [Current State](CURRENT_STATE.md).

## Latest Phase 3D-R4C Disposition

**`PAC_AUTH_CONTEXT_UNAVAILABLE` — stop before fresh environment reconciliation or package push.** The active local PAC profile is labeled `O-SR-port` and names VN LMV IT as its environment. Its reported token expiry is 24 October 2026, before this continuation on 25 October. The mandatory fresh `pac org who` verification was not run after the expired-token indication. No interactive login, PRT launch, PAC profile selection, or environment switch was attempted.

The frozen local package remains at the approved path and its SHA-256 (`41a18a66aabf0c75356209e6814d93f60aa6d4dc2eebd3a965d9291b3bb8b59b`) and contained DLL SHA-256 (`ba332f58c55c8c13b8eb44df619b8236022f78261b7a02099890b3281a88aaf1`) match the retained R4 artifact. This local check does not establish live package state. The R4B section below records one package row and generated assembly/types; the R4C authorization text says those generated components were not produced by raw package-row creation. Because the authentication gate failed, this discrepancy was not rechecked live. Do not repeat package creation or push until a valid PAC context allows fresh read-only reconciliation.

| R4C action | Count / disposition |
|---|---|
| Local artifact check | Frozen package and DLL hashes exact; artifact not rebuilt |
| Fresh `pac org who` / live metadata reconciliation | Not performed after expired-token indication |
| PAC auth-who profile inspection | Target profile identified; tool does not expose a reliable GET count |
| Fresh package / assembly / type / API / Solution reads | Not performed |
| Raw PluginPackage POST | 0 |
| `pac plugin push` | 0 |
| Custom API handler PATCH / rollback PATCH | 0 / 0 |
| Business API invocations / business-data writes | 0 / 0 |
| Legacy assembly / schema / app writes | 0 / 0 / 0 |
| Automatic retries | 0 |
| Package-backed assemblies / plug-in types observed in R4C | Not queried |
| Commit / push | 0 / 0 |

The auth-who tool's underlying GET count is unknown; no deployment or runtime runner GET was dispatched. Primary result is `PAC_AUTH_CONTEXT_UNAVAILABLE`. Resume only with an already-approved, non-interactive PAC context and fresh target/identity confirmation. See [Current State](CURRENT_STATE.md).

Offline validation: all 10 existing PowerShell suites passed (1,094 assertions); the Candidate Core engine harness passed 79 assertions; the SDK adapter/guard harness passed 56 assertions; the package artifact suite passed 12 assertions; and the R4B deployment-contract suite passed 23 assertions. All 20 PowerShell files parsed, the added-line privacy scan passed, 58 relative links in the modified documents resolved, and `git diff --check` passed. No dedicated PAC NuGet push command-plan test exists in the current test tree; the R4B deployment-contract suite covers the prior direct Web API upload path, not `pac plugin push`. No package rebuild or tenant operation was performed during validation.

## Latest Phase 3D-R4B Disposition

**`PLUGIN_PACKAGE_PROCESSING_FAILED` — stop before Custom API handler cutover or runtime acceptance.** After the fresh read-only gates passed, the guarded direct Web API runner dispatched one authorized package POST. Immediate GET reconciliation found exactly one package record and verified its name, unique name, version, and approved Solution membership. Both the collection GET and a later strong-consistency direct GET returned no nonempty `content`, so the frozen package SHA-256 could not be verified. Live metadata reports the Content column as valid for read; the missing GET value is an unresolved content-reconciliation gap, not proof that the content was absent or incorrect. Microsoft's [Plugin Package table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/pluginpackage) also lists Content as a readable column.

### Package processing evidence

The read-only post-stop inspection confirmed:

| Check | Live result |
|---|---|
| Package record count | 1 |
| Package name / unique name / version | Exact: `os_sr_cact_pkg` / `os_sr_cact_pkg` / `1.0.0` |
| Approved Solution membership | Exact |
| PluginPackage entity set / primary ID | `pluginpackages` / `pluginpackageid` |
| Content field readback | No nonempty value from collection or direct GET; expected package hash not verified |
| Package-to-assembly relationship | One relationship; lookup attribute `packageid` |
| Generated assembly | One `os_sr_cact`, version `1.0.0.0` |
| Assembly SourceType | `File Store` |
| Generated plug-in types | Exactly `os_sr_cact.ApplyCandidateAction` and `os_sr_cact.ProtectCandidateCore` |

The expected package SHA-256 remains `41a18a66aabf0c75356209e6814d93f60aa6d4dc2eebd3a965d9291b3bb8b59b`; the contained DLL SHA-256 is `ba332f58c55c8c13b8eb44df619b8236022f78261b7a02099890b3281a88aaf1`. The live record did not expose a content value to hash, so neither exact package-content identity nor full package reconciliation is claimed. Generated assembly/type evidence confirms package processing, but does not satisfy the missing content fingerprint gate.

### Fresh gates, writes, and acceptance boundary

The new read-only R4B preflight returned `PLUGIN_PACKAGE_PREFLIGHT_READY`. Its initial JSON total was 626 GETs, but that aggregate omitted the strict legacy runner's separately reported 77 storage-gate GETs. Corrected accounting is 703 GETs: 63 package-runner, 508 strict legacy/API/guard, 77 strict storage-gate, 46 separate storage, and 9 fresh zero-row runtime-gate GETs. It verified the exact package was absent before Apply and all four business/evidence table counts were 0. It made 0 POST/PATCH calls and 0 retries. The deployment runner's aggregate count was corrected locally to include the nested storage gate.

The Apply run made 705 GETs in aggregate: 65 package-runner, 508 strict legacy/API/guard, 77 strict storage-gate, 46 separate storage, and 9 zero-row-gate GETs. The package-runner failure JSON reported only its own 65 GETs; the aggregate includes the separately counted sub-runner GETs. It dispatched exactly one `POST pluginpackages`, then stopped on the absent content readback.

| R4B action | Count / disposition |
|---|---|
| Fresh package preflight | 703 corrected GETs; package absent; 4 business/evidence counts 0 |
| Apply read-only gates | 705 aggregate GETs; strict legacy baseline exact before create |
| Package create | 1 POST; one package record and generated assembly/types found |
| Content fingerprint reconciliation | Not proven; no nonempty content returned |
| Custom API handler PATCH | 0 |
| Rollback PATCH / package delete | 0 / 0 |
| Post-stop GET-only reads | Package inspection: 11 GETs; generic strict reconciler: 255 direct + 77 storage-gate GETs, stopped because its global inventory expects one assembly; expanded targeted inspection: 66 GETs; follow-up including direct package GET: 67 GETs |
| Post-stop exact handler check | API contract exact; API still points to legacy handler; legacy assembly hash and all 50 guard steps exact |
| Total post-stop GETs | 476; 0 POST/PATCH |
| Final fresh preflight + Apply + post-stop GET total | 1,884 |
| Runtime Custom API invocations | 0 |
| Candidate / Call Log / History / Receipt business writes | 0 |
| Automatic retries | 0 |
| Organization auditing, schema, Choices, security, app, publication | No changes |
| Commit / push | 0 / 0 |

The package remains in the approved Solution. The one-shot deployment journal records the package POST dispatch; do not retry or delete the package. The API-handler cutover was not attempted, and runtime acceptance was not started. No synthetic Candidate was created. The older generic reconciler stopped because it expects one total assembly and now sees the legacy plus package-generated assembly. A separate targeted GET-only inspection confirmed the API contract, legacy handler mapping, legacy assembly hash, and guard-step topology after the package POST.

Local validation after these code changes: all 10 PowerShell suites passed 1,094 assertions; the Candidate Core operation-engine harness passed 79 assertions; an existing offline Candidate Core SDK adapter/guard executable passed 56 assertions and was not rebuilt because the strong-name key remains unapproved. All 20 PowerShell files under `scripts/` and `tests/` parsed with zero errors; the added-line privacy scan passed; 76 relative Markdown links resolved; and `git diff --check` passed. The new [R4B deployment assertions](../tests/Phase3DR4BPluginPackageDeployment.Tests.ps1) include 23 checks; the runtime contract suite passed 18 checks. The package artifact itself was not rebuilt in this continuation; the frozen package and DLL hashes remain the previously verified local artifact values.

The repository remains on branch `main` at HEAD `cff0033`; the R4B runner, tests, and documentation changes are uncommitted. No commit or push was made.

Next work is read-only investigation of a supported way to reconcile `pluginpackage.content`. Preserve the created package and all existing mappings. No second package POST, delete, handler PATCH, runtime API call, or other tenant write follows from this stop result. See [Current State](CURRENT_STATE.md) and [test guide](../tests/README.md).

## Historical Phase 3D-R4 PRT Authentication Stop (2026-10-25; superseded by R4B)

**`PLUGIN_PACKAGE_CREATE_BLOCKED_AUTH` — stop before package registration, Custom API handler cutover, or runtime acceptance.** The unsigned package artifact is locally built and verified. Fresh Candidate Core and zero-row gates passed; the approved package is absent by exact-name query. PRT was installed, but its single current-user login attempt failed before organization selection. No tenant mutation or API invocation was dispatched.

### Local package artifact

| Item | Result |
|---|---|
| Package project | [CandidateCore.Package.csproj](../solutions/CandidateCorePackage/CandidateCore.Package.csproj), SDK-style .NET Framework 4.6.2 |
| Package identity | `os_sr_cact_pkg`, version `1.0.0` |
| Contained assembly identity | `os_sr_cact`, version `1.0.0.0`, unsigned / no public-key token |
| Included plug-in types | `os_sr_cact.ApplyCandidateAction`; `os_sr_cact.ProtectCandidateCore` |
| Package contents | One `lib/net462/os_sr_cact.dll` plus NuGet metadata; no PDB, key, or additional assembly |
| Package SHA-256 | `41a18a66aabf0c75356209e6814d93f60aa6d4dc2eebd3a965d9291b3bb8b59b` |
| Contained DLL SHA-256 | `ba332f58c55c8c13b8eb44df619b8236022f78261b7a02099890b3281a88aaf1` |
| Repeatability | Clean Release build and subsequent build both succeeded with 0 warnings / 0 errors and identical package SHA-256 |
| Legacy signed local assembly | Remains `os_sr_cact` v1.0.0.0, token `d73b02688ba7f9aa`, SHA-256 `089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85`; unchanged for rollback |

The package test is [Phase3DR4PluginPackage.Tests.ps1](../tests/Phase3DR4PluginPackage.Tests.ps1): it verifies project/package identities, exact package entries, no signing material, unsigned assembly identity, and both contract types using local reflection. It passed 12 assertions. All nine PowerShell suites passed 1,070 assertions; the Candidate Core operation-engine suite passed 79 assertions. The package links the current Candidate Core source without modifying it.

### Registration stop and exact boundary

PAC CLI is version 2.13.1. The [PAC plug-in command reference](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/plugin) shows that `pac plugin push` requires `--pluginId` (an assembly or package ID), but does not establish that an arbitrary new ID creates a first-time package. Microsoft's [PAC CLI package guide](https://learn.microsoft.com/en-us/power-platform/developer/howto/cli-create-package) documents first-time registration through the Plug-in Registration Tool and selection of an existing Solution. PRT 9.1.0.235 was installed locally and opened. Two current-user sign-in attempts (standard Office 365 followed by OAuth) returned a generic login error before organization selection. No credentials were entered, no error log was inspected, and no further authentication retry was made. PAC's existing profile remained unchanged and PAC `org who` continued to verify the expected VN LMV IT organization and user. Because no authenticated PRT session was available and first-time PAC push semantics were not verified, no package ID was guessed and no upload was attempted.

### Fresh deployment and runtime gates

Immediately before the PRT registration attempt, the existing strict reconciler returned `CANDIDATE_CORE_ASSEMBLY_RECONCILED`: 508 GETs (77 storage-gate GETs), 0 POST, 0 PATCH, 0 retries. Storage, Solution/Publisher, API/privilege, assembly, and registration inventory matched the retained exact plan and dispatch evidence. The separate runtime preflight returned `PHASE_3D_RUNTIME_PREFLIGHT_READY`: 9 count-only GETs; Candidate, Call Log, History, and Receipt rows were each 0; API invocations, business writes, audit-setting writes, and retries were all 0. A targeted live FetchXML query filtered the `pluginpackage` table to the exact approved name `os_sr_cact_pkg` and returned no row. PRT authentication failed before selecting an organization, so it did not alter or register a Dataverse component.

| R4 action | Count / disposition |
|---|---|
| Local package builds | 2 successful Release builds; 0 warnings / 0 errors |
| Package assertions | 12 passed |
| All PowerShell suites | 9 suites; 1,070 assertions passed |
| Candidate Core operation-engine suite | 79 assertions passed |
| Fresh registration/storage reconciliation | 508 GETs, including 77 storage-gate GETs; 0 POST/PATCH; exact match |
| Fresh runtime count preflight | 9 GETs; all four business/evidence counts 0 |
| Exact-name package query | 1 targeted FetchXML operation; no matching row |
| PAC / PRT operations | PAC 2.13.1 profile/WhoAmI verified; PRT 9.1.0.235 installed; 2 login failures before organization selection |
| Package create/upload dispatches | 0 |
| Package Solution-membership writes | 0 |
| Custom API handler patches | 0 |
| Plug-in type/step or legacy assembly changes | 0 |
| Runtime API invocations / business-row writes | 0 / 0 |
| Automatic retries | 0 |
| Commit / push | 0 / 0 |

No package component or handler mapping is treated as deployed. The package-name query establishes no matching row at query time; it does not establish that other package records are absent.

The existing legacy `ProtectCandidateCore` registrations and signed assembly were not changed. Any later package cutover must freshly reconcile guard-step topology and preserve the approved direct-write protections. Only after supported first-time package registration, exact Solution membership/type reconciliation, and fresh API/step baseline should the single authorized `PluginTypeId` handler cutover be considered. No schema, Choice, API signature, security, app, organization-audit setting, or publication change is in scope.

### Repository and acceptance status

Starting repository baseline: branch `main`, HEAD `7ee75166a654ddafc24133fa51cc8dafdd9bebcc`. R4 work remains uncommitted; no commit or push was made. The only R4 repository changes are the package project, package assertions, and existing Phase 3D/current-state/test-guide documentation. Local package artifact output is build output only.

The final R4 result is an authentication stop, **not** a failed or uncertain tenant write. The R3 signing-key classification remains `SIGNING_KEY_ACL_NOT_APPROVED` for the old individually signed build path; the key was not used. The future package registration is a separate dependency. No live runtime acceptance is claimed.

## Historical Phase 3D-R3 Disposition

**`SIGNING_KEY_ACL_NOT_APPROVED` — stop before build, fresh live pre-deployment reads, assembly deployment, or runtime acceptance.** The extra inherited `FullControl` principal resolves to a disabled local account, but its organizational/build trust cannot be established. It is classified `UNRESOLVED_PRINCIPAL`; disabled status and local-account resolution do not establish trust.

### Repository and source baseline

The read-only baseline was branch `main`, HEAD and `origin/main` `4858c77b05ae38e14266ec5685dabd8f460115d7` (2026-10-25 12:01:09 +07), with a clean worktree before this documentation update. The committed source already contains the approved optional/null/empty-Guid `CandidateId` CreateCandidate handling and its regressions. No source or test code changed in this continuation.

The signing-key reference is the retained session artifact `phase3c-plugin-signing.snk`; the tracked-safe reference is `session-state/files/phase3c-plugin-signing.snk`. Reference-string SHA-256: `b1d05fbb1b87ad61` (this is a hash of the normalized reference string, not of the key). Key bytes were not read, copied, exported, or hashed.

### Sanitized ACL and provenance

The key owner resolved to the current authorized user. ACL inspection found inherited `Allow / FullControl` entries for SYSTEM, local Administrators, the current authorized user, and one additional disabled local account. The additional account's SID is withheld; its non-reversible reference is `828623bbe96d3f20`. Its ACE is inherited from an explicit ACL on a common profile-root ancestor; the exact path is suppressed. No ACL, account, group, membership, or ownership change was made.

| Principal | ACE | Provenance / disposition |
|---|---|---|
| SYSTEM (`S-1-5-18`) | Allow / FullControl; inherited | Built-in system principal; exact inheritance source not retained |
| Local Administrators (`S-1-5-32-544`) | Allow / FullControl; inherited | Local administration group; exact inheritance source not retained |
| Current authorized user (SID suppressed) | Allow / FullControl; inherited; owner | Resolved to the current operator; exact inheritance source not retained |
| Additional disabled local account (SID reference `828623bbe96d3f20`) | Allow / FullControl; inherited | ACE is explicit at a common profile-root ancestor; trust unresolved |

No Deny ACE was observed in the inspected key ACL.

Because the additional principal cannot be conclusively classified as trusted, the existing key is not approved for use. No attempt was made to change ACLs, disable inheritance, take ownership, or create/use a replacement key.

### Strong-name identity and stop boundary

The existing local `os_sr_cact.dll` was inspected read-only: assembly name `os_sr_cact`, version `1.0.0.0`, public-key token `d73b02688ba7f9aa`, SHA-256 `089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85`. This matches the previously reconciled deployed binary's public identity and hash; it does not authorize use of the private key. No signed build was attempted, so corrected-binary signing, test results against a signed build, and corrected DLL hash remain unavailable.

| R3 activity | Result |
|---|---|
| Signing-key ACL / identity resolution | Read-only; additional account trust unresolved; key use not approved |
| Candidate Core source / expected identity | Existing optional `CandidateId` correction retained; expected token matches inspected local assembly |
| PowerShell suites | 8 suites; 1,058 assertions passed |
| Candidate Core operation tests | 79 assertions passed |
| Parser / `git diff --check` before documentation edits | Passed |
| Fresh live pre-deployment GETs / tenant operations | 0 / 0 |
| Signed build / corrected DLL hash | 0 / unavailable |
| Assembly update | 0 |
| API/schema/app/security/audit/publication writes | 0 |
| Business API invocations / business-row writes | 0 / 0 |
| Automatic retries | 0 |
| Commit / push | 0 / 0 |

The next architectural option, `MIGRATE_INDIVIDUAL_ASSEMBLY_TO_PLUGIN_PACKAGE`, is recorded only as a future proposal; no migration or deployment-model change was made. Resume only under a separately authorized and approved protected signing mechanism. Do not alter this key's ACL or use it based on the unresolved account.

## Latest Phase 3D-R2 Disposition

**`SIGNING_KEY_UNAVAILABLE` — no build, tenant read, assembly update, or runtime request was made in this continuation.**

### Baseline and defect assessment

At R2 start the repository was `main`, clean, and at HEAD/origin/main `b90d25bc29ffb1a75e5be7bc8f07c91b5315a526` (2026-10-25 07:43:18 +07). The Candidate Core manifest remained `63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915`. The deployed assembly remained the previously reconciled `os_sr_cact`, version `1.0.0.0`, hash `089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85`. Expected public-key token: `d73b02688ba7f9aa`.

The approved API contract file marks `CandidateId` optional (`optional: true`); the prior Phase 3C deployment report records that only `ActionType` and `CorrelationId` were metadata-required. R2 did not perform a fresh live metadata read because the mandatory signing-key safety gate failed first. The previous runtime request failed with HTTP 400 / `0x80040265` / `UNEXPECTED_INPUT`. The former handler rejected CreateCandidate if the optional `CandidateId` key was present, even with a null value. That source path is a strong, plausible root cause for the observed error, but the live response alone does not identify the offending input with certainty.

The local handler now applies these CreateCandidate rules:

| Input | Local behavior |
|---|---|
| CandidateId omitted | Accepted |
| CandidateId null | Accepted |
| CandidateId empty Guid | Treated as the empty optional representation |
| CandidateId non-empty valid Guid | Rejected as `UNEXPECTED_INPUT`, preserving the approved Create semantics |
| CandidateId wrong type | Rejected deterministically as `INVALID_CANDIDATEID` |
| Unknown parameter / missing required name or email | Rejected; invalid requests do not mutate the store |

The regression tests also verify audit-inactive synthetic CreateCandidate behavior and preserve existing operation, replay, transaction, actor, and fail-closed transition tests. This local source is not built or deployed.

### Signing boundary and stop

The previously retained signing artifact was found by its session-artifact name, but its inherited ACL granted FullControl not only to the current user, SYSTEM, and local Administrators, but also to an additional principal that could not be verified as part of the approved signing boundary. The key owner also did not resolve to an approved category. No key bytes were read, no permissions were changed, and no alternate or replacement key was generated. The key therefore was not used. Per the owner instructions, stop classification is `SIGNING_KEY_UNAVAILABLE`.

The source fingerprint for `solutions/CandidateCore/Operation.cs` after the local correction is `772e2d443a240d377f5a568b357f60e3e907cb7da33c362f78f3d7c7c2936dd4`; Candidate Core test source fingerprint is `b5648cc1111b2d9552474af6caf608bf3bdf61d52864009291841299880f0d1b`. The corrected DLL hash is unavailable because it was not built. Strong-name identity continuity, current live API optionality, and deployment reconciliations were therefore not tested in R2.

| R2 activity | Result |
|---|---|
| PowerShell suites before deployment | 8 suites, 1,058 assertions passed |
| Candidate Core operation tests | 79 assertions passed |
| Parser / `git diff --check` | Passed |
| Fresh live pre-deployment reads | 0 |
| Plug-in build / corrected DLL hash | Not attempted / unavailable |
| Assembly update | 0 |
| API metadata / schema / app / role / audit-setting / publication writes | 0 |
| CreateCandidate / other business API invocations | 0 / 0 |
| Business-row creates / cleanup deletes | 0 / 0 |
| Automatic retries | 0 |
| Commit / push | 0 / 0 |

The changes now in the worktree are limited to the CreateCandidate optional-input correction, its tests, and this report/Current State update. HEAD remains unchanged; no commit or push was made. Do not alter the key ACL, use this key, deploy the local binary, or consume another runtime attempt without an approved protected signing mechanism and the applicable bounded authorization.

## Latest Phase 3D-R Continuation Disposition

**`PHASE_3D_RUNTIME_STOPPED` — the first live Custom API request was definitively rejected; runtime acceptance is incomplete.** No retry or further dispatch was made after the rejection.

Fresh GET-only reconciliation matched the current Candidate Core manifest, storage, Operation Receipt and Active alternate key, Solution/Publisher, Custom API contract and privilege, plug-in types and registrations. It returned `CANDIDATE_CORE_ASSEMBLY_RECONCILED`, with assembly SHA-256 `089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85`; organization auditing remains disabled. The approved audit-gate-decoupled assembly was already deployed, so this continuation dispatched no assembly update. The original consumed Phase 3D lock was preserved.

The repository baseline was `main`, HEAD and `origin/main` both `ef5b512e33e38f08fece1db439558afd029e8baf` (2026-10-24 20:50:38 +07), with manifest SHA-256 `63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915`. The worktree was clean at the start; the six current changes are limited to the Phase 3D report/current state, guarded deployment error reporting, the runtime runner, and its offline assertions. No commit or push occurred. The local plug-in source already lacks the organization-audit runtime rejection; no source rebuild or assembly update was needed for this continuation.

Immediately before Apply, a fresh guarded preflight returned **9 GETs**, zero Candidate, Call Log, Candidate Status History, and Operation Receipt rows, zero API invocations, and zero retries. The new authorization-specific lock/evidence identity was unused; a distinct lock was created without changing the historical lock.

The runner dispatched **one** `CreateCandidate` Custom API request. Dataverse returned HTTP 400, error code `0x80040265`, `UNEXPECTED_INPUT`. The request was rejected; no further action in the matrix was sent. A subsequent guarded count-only preflight returned **9 GETs** and zero rows in all four tables. No Candidate ID or other business-record identifier was created or retained. Organization auditing was not changed.

| Evidence | Phase 3D-R result |
|---|---|
| Current assembly reconciliation | `CANDIDATE_CORE_ASSEMBLY_RECONCILED`; 508 GETs, including 77 storage-gate GETs; 0 POST/PATCH |
| Earlier read-only reconciliation diagnostic | 257 GETs; stopped locally on an omitted expected plan fingerprint; 0 writes |
| Organization auditing | Disabled; unchanged; external governance/release prerequisite, not a runtime gate |
| Pre-Apply zero-row gate | 9 GETs; all four row counts 0 |
| Custom API dispatch | 1 `CreateCandidate`; HTTP 400; `0x80040265`; `UNEXPECTED_INPUT` |
| Other Custom API dispatches | 0; the rest of the matrix was not reached |
| Post-rejection zero-row gate | 9 GETs; all four row counts 0 |
| Successful business-data writes / resulting rows | 0 / 0 |
| New authorization-specific one-shot guard | Consumed; preserved |
| Prior Phase 3D one-shot guard | Preserved; not reused |
| Automatic retries / resends | 0 / 0 |
| Metadata, app, role, audit-setting, publication writes in this continuation | 0 |

The runtime dispatch journal records the request as `REJECTED` with HTTP 400, but its `ResultCode` is null because the runner's allowlist did not yet include `UNEXPECTED_INPUT`. The sanitized command result captured that Dataverse code. The local allowlist was updated afterward; the retained journal was not rewritten. The GET figures above are per captured operation result; diagnostic preflight invocations whose wrapper output was not preserved are not included in an aggregate total.

The local runner and contract assertions now reflect the authorized **eight-dispatch** matrix and expected maximum effects of one Candidate, two Call Logs, two History rows, and four Receipts (nine total rows). This describes the bounded test plan, not live acceptance: execution stopped at the first rejected request. `MarkRound1Scheduled` and the remaining scheduled/result/reschedule checks were not invoked. Offline operation tests verify the scheduler evidence rejection and the result/reschedule evidence guards; the latter actions are `NOT_APPLICABLE_CURRENT_STATE` live because no Candidate was created. Non-admin user/role acceptance remains deferred to the Candidate UI + Security phase.

Do not remove either lock, recreate or reuse the evidence file, or rerun Apply. The rejected request was not resent. Further live acceptance requires a separately bounded authorization after the `UNEXPECTED_INPUT` request-contract/runtime boundary is diagnosed. No cleanup or speculative request was attempted.

### Local Validation in This Continuation

After the rejection, local inspection found a plausible contract-boundary defect: `CandidateId` is an optional Custom API input, but `ActionRequest` rejected CreateCandidate whenever the input dictionary contained the key, including when Dataverse supplied it as null. The local implementation now rejects only a non-null CandidateId on CreateCandidate, with offline tests for both null acceptance and non-null rejection. This is a narrowly scoped local correction, not deployed; the live 400 does not identify which individual input caused `UNEXPECTED_INPUT`, so the diagnosis remains to be confirmed by a separately authorized deployment/runtime attempt.

All eight PowerShell suites passed **1,057 assertions** before the local root-cause correction; after correction, the focused Phase 3D suite passed **17 assertions** and the Candidate operation engine passed **72 assertions**. `git diff --check` and PowerShell parsing passed. The Candidate Core SDK adapter test could not build in this session because no protected `CandidateSigningKey` was configured; no signing material was searched for or exposed. The full PowerShell suites were not rerun after the last targeted correction. These local checks do not establish live operation acceptance.

The local correction does not authorize another assembly update or runtime dispatch. The prior assembly update and authorization-specific one-shot runtime request have already been used; preserve both locks/journals and do not retry or deploy without fresh bounded owner authorization.

The sections below preserve earlier assessments. The former `UNCERTAIN_WRITE_OUTCOME` disposition is superseded by this definitive HTTP 400 rejection; the original `TRANSITION_CONTRACT_FAILURE` is also historical.

## 1. Executive Summary (Historical pre-runtime assessment)

**`TRANSITION_CONTRACT_FAILURE`**

No Candidate fixture or business API invocation was made. Fresh metadata reconciliation passed, but execution must stop before data creation because the deployed operation rejects all business operations while organization auditing is disabled, the requested booking/result/reschedule paths are intentionally fail-closed in the approved contract, and no approved cleanup mechanism is established for records protected by the direct-write guards and restrictive relationships. The classification denotes an acceptance-scope incompatibility, **not a confirmed runtime defect**.

The user authorized synthetic data despite pending organization-level audit activation. That authorization does not authorize bypassing the deployed audit gate, changing plug-in behavior, weakening write guards, or leaving synthetic history behind. The approved API and deployment remain unchanged.

## 2. Repository / Manifest Baseline (Historical)

| Item | Observed |
|---|---|
| Repository / branch | BSO-RS-Support / `main` |
| HEAD | `9e15357ffef1ba011f65053f61c48047050ba68f` |
| HEAD timestamp | `2026-10-24T19:14:02+07:00` |
| `origin/main` | Same as HEAD at inspection |
| Initial worktree | Clean |
| Candidate Core manifest SHA-256 | `63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915` |
| Receipt contract SHA-256 | `f26116c87e62c3a2faeecdf5e0a63a0ceef20069bdb78d36d9386a73dfed2efc` |
| API contract SHA-256 | `a6f8295df1f72a160c0490b49d457d7c0a6d82e23a3fcac8f1a68aa66b6bbaa9` |

No fetch, commit, push, branch change, or deployment-plan change was made. This report and the synchronized current-status documentation are the only intended repository edits for this run.

## 3. Environment / Identity

The fresh guarded reconciliation matched the owner-authorized VN LMV IT target, the active PAC context, the Dataverse WhoAmI identity, and the process-scoped expected-user guard. Identity values, organization URL, and tenant/environment identifiers are intentionally omitted.

The Power Platform CLI read-only authentication/profile, environment table inventory, Solution inventory, and security-role inventory commands were also used. The profile output contained personal/tenant identifiers and is not reproduced here.

## 4. Live API / Plug-in Baseline (Historical Phase 3C baseline)

Fresh GET-only reconciliation confirmed the existing Candidate Core tables, Operation Receipt and Active alternate key, assembly and types, 50 registration steps, Custom API, all request/response metadata, `ExecutePrivilegeName=prvWriteos_sr_cand`, and Solution membership. The final result remained `CANDIDATE_CORE_API_DEPLOYED_AUDIT_ACTIVATION_PENDING`; no drift was found and nothing was redeployed.

The Phase 3C baseline assembly SHA-256 was `f11d6db0db3a190806ef48daa46a3f3b6befbf7070f236bac5a44b6e40598f0f`; it was superseded by the Phase 3D-R assembly recorded above. The API is the private unbound `os_sr_cact` Action implemented by `os_sr_cact.ApplyCandidateAction`.

## 5. Organization Audit State (Historical pre-correction assessment)

At the time of the historical pre-correction assessment, organization-level auditing was disabled and the earlier assembly enforced an audit runtime gate. The current assembly no longer rejects solely for this setting. Table audit metadata is not a substitute for organization-level audit activation, which remains externally pending.

The owner authorized the bounded synthetic test while this condition remains pending. No audit setting was changed. The later `UNEXPECTED_INPUT` rejection is separate from organization audit state.

## 6. Synthetic Reference Fixtures

The current manifest makes Position and Candidate Source optional for Candidate creation; the TA lookup is conditional before booking. No reference fixture is required for the supported create/call slice. Booking is unavailable in the current API contract. No reference rows were created.

## 7. Candidate Fixture Creation

Candidate A created: **0**. Candidate B created: **0**. No synthetic names, email addresses, or other candidate fields were submitted to Dataverse.

## 8. AutoNumber Runtime Result

Not tested. `AUTONUMBER_RUNTIME_GENERATION_VERIFIED` is **not** claimed.

## 9. RecordCall - No Answer

Not invoked. No Call Log or Operation Receipt was created.

## 10. Identical Replay

Not invoked live. Offline engine assertions cover persisted-result replay, but do not establish deployed Dataverse behavior.

## 11. Conflicting Replay

Not invoked live. Offline engine assertions cover conflicting reuse and uniqueness races; they do not establish deployed Dataverse behavior.

## 12. RecordCall - Answered

Not invoked. Candidate transition, Call Log, History, actor, and receipt effects have no live acceptance evidence from this run.

## 13. Normal Transition Path

No live transition was attempted. `ProceedToScheduling` is present in the current API contract, but organization auditing is disabled and the deployed code fails closed before business effects.

The requested Waiting Manual Scheduling to Round 1 Scheduled success path is not currently supported: `MarkRound1Scheduled` requires trusted scheduler evidence which the deployed API does not accept.

## 14. Reschedule

Not invoked. The approved design and frozen API contract explicitly defer `RequestReschedule` until the later cancellation-attempt evidence boundary exists. The Phase 3D requested success expectation conflicts with that approved fail-closed behavior. No calendar call or cancellation was attempted.

## 15. Stale-State Rejection

Not invoked live. Existing offline assertions verify stale expected status and row-version rejection in synthetic adapters only.

## 16. Offer Extended Terminal Path

Not tested live. The deployed API requires trusted result evidence for `RecordPass`; it remains unavailable in the current contract. No terminal status or rollback request was made.

## 17. Candidate Failed Terminal Path

Not tested live. The deployed API requires trusted result evidence for `RecordFail`; it remains unavailable in the current contract. No terminal status or rollback request was made.

## 18. Transaction / Atomicity Evidence

No live operation was dispatched, so transaction atomicity is **not verified**. Offline host rollback simulations and SDK adapter tests are synthetic unit evidence only.

## 19. Actor Semantics

No live business actor or child row was produced. Caller-context/initiating-user behavior has metadata and offline harness evidence, not live Phase 3D acceptance evidence.

## 20. Operation Receipt Evidence

No receipt row was created or read for this run. Receipt schema and Active uniqueness key remain reconciled; live replay and receipt privacy/result behavior were not exercised.

## 21. Non-admin Test-User Discovery

**`NON_ADMIN_TEST_USER_NOT_AVAILABLE`** for this acceptance run. The available CLI role inventory is not a user/licensing enumeration and does not establish a suitable licensed non-admin Candidate caller. No user identity was selected, disclosed, or granted access. No security change occurred. This classification does not claim that the environment contains no non-admin users.

## 22. Synthetic Cleanup

No rows were created, so cleanup actions dispatched: **0**.

Before creating fixtures, source review established that Candidate Core direct Create/Update is accepted only under the exact validated `os_sr_cact` parent operation; direct Delete/DeleteMultiple is rejected by the deployed guard. Candidate-to-Call/History relationships use restrictive deletion, and there is no approved delete operation in the Custom API. The repository/tooling inspected did not establish a narrowly scoped approved administrative cleanup mechanism that bypasses those protections. No plug-in bypass or alternate delete path was attempted.

## 23. Post-Cleanup Verification

No cleanup was needed. Four sequential count-only FetchXML queries returned **0** for Candidate, Call Log, Candidate Status History, and Operation Receipt. The metadata/API reconciliation was read-only and exact. These are fresh pre-test counts; they do not represent cleanup of this run's records.

## 24. Request / Business Write Counts

| Category | Count |
|---|---:|
| Guarded instrumented GETs (deployment/storage reconciliation) | 335 |
| Count-only FetchXML queries | 4 |
| Custom API invocations | 0 |
| Candidate / Call Log / History / Receipt business writes | 0 |
| Reference-data writes | 0 |

The 335 GET total is the runner's instrumented Web API count (258 registration/identity plus 77 storage-gate reads). Tool-mediated CLI internals and PAC/authentication informational reads are not included in that count.

## 25. Metadata Write Counts

| Category | Count |
|---|---:|
| Schema / Choice / relationship / key writes | 0 |
| Plug-in deployment writes | 0 |
| Custom API / parameter / response writes | 0 |
| App writes | 0 |
| Role / team / security writes | 0 |
| PublishXml / PublishAllXml | 0 / 0 |
| Automatic retries | 0 |

## 26. Retry vs Explicit Replay Counts

Transport retries: **0**. Explicit replay-test API calls: **0**. Conflicting-replay API calls: **0**. No business operation was invoked.

## 27. Offline / Regression Results

All nine local suites passed, **1,157 assertions**:

| Suite | Assertions | Result |
|---|---:|---|
| Phase 3A design | 46 | PASS |
| Phase 3B.2 provisioning | 50 | PASS |
| Reference provisioning | 550 | PASS |
| Readiness | 11 | PASS |
| Model-driven app composition | 329 | PASS |
| Phase 3C receipt contract | 27 | PASS |
| Phase 3C deployment contract | 23 | PASS |
| Candidate operation engine | 68 | PASS |
| SDK adapter / guards | 53 | PASS |

Passing offline tests do not prove live Custom API execution, organization transaction behavior, effective non-admin privileges, AutoNumber generation, or live cleanup.

## 28. Files Changed

- This report.
- [Current State](CURRENT_STATE.md).
- [Master Production Rules](../MASTER_PRODUCTION_RULES.md).
- [Project Context](PROJECT_CONTEXT.md).
- [Implementation Plan](IMPLEMENTATION_PLAN.md).
- [Test Strategy](TEST_STRATEGY.md).
- [Security Model](SECURITY_MODEL.md).

No production source, contract, manifest, deployed metadata, or environment setting changed.

## 29. Final Runtime Classification

**`TRANSITION_CONTRACT_FAILURE`**

The Phase 3D acceptance requirements conflict with the currently approved/deployed fail-closed contract, and the audit gate prevents all business operations. No live behavior failure was observed because no business API was invoked. This result means **runtime acceptance not performed**, not that supported actions were proven broken.

## 30. UI / Security Readiness

**Not yet ready to claim `READY_FOR_CANDIDATE_UI_AND_SECURITY` under the Phase 3D exit rule.** No runtime acceptance passed, and no suitable non-admin caller was established. The deployed metadata is intact; the UI/security stage must not assume live business-operation acceptance.

## 31. Outstanding Governance Items

- IT/Compliance organization-audit activation, retention, access, capacity, and evidence governance remain pending.
- No approved least-privilege non-admin Candidate caller role/user acceptance is established.
- Trusted scheduler booking evidence, result evidence, and cancellation-attempt evidence remain future dependencies.
- A bounded, approved cleanup procedure for synthetic records protected by current guards must be established before any future fixture creation.

No audit, security, or product behavior settings were changed.

## 32. Exact Recommended Next Task

First reconcile the Phase 3D test matrix with the approved Phase 3C contract. Either:

1. keep booking/result/reschedule out of this acceptance until their trusted evidence boundaries are implemented and separately authorized; or
2. obtain explicit product/security approval for a changed contract and implement those evidence boundaries in a separately authorized phase.

Before creating any live fixtures, resolve organization auditing or obtain a separately approved test-only runtime approach that does not bypass the deployed fail-closed guard, establish an exact-ID cleanup method that preserves write protections, and verify a licensed non-admin test identity/role without granting access in this phase. Then issue a new bounded test authorization. Do not invoke production APIs or create records based on this report alone.

## 33. AI HANDOVER

Phase 3C metadata remains exact and deployed as `CANDIDATE_CORE_API_DEPLOYED_AUDIT_ACTIVATION_PENDING`. Current manifest, receipt contract, API contract, plug-in bytes, and registration metadata were not changed. Four business/evidence tables had zero rows in fresh count-only reads. This Phase 3D run created no fixtures and invoked no Custom API.

Do not report AutoNumber, live replay/conflict, transaction atomicity, actor, terminal-state, reschedule, or cleanup behavior as accepted. The current API intentionally rejects scheduler/result/reschedule actions until trusted evidence exists and rejects business execution while organization auditing is disabled. Next work is contract/governance/cleanup reconciliation, not a test-data retry.
