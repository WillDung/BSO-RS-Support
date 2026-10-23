# Model-driven App and Sitemap Automation Runbook

**Current status - Phase 2D.3P navigation verified (2026-10-23):** The separately authorized single Site Map PATCH returned HTTP 204. GET-only reconciliation verified exact reference navigation in an unpublished draft, unchanged published XML, the same 13 components, unchanged roles, and clean ValidateApp. `srapp` remains Active/Unpublished. Outcome: `VERIFIED_REFERENCE_NAVIGATION_UNPUBLISHED`. The authorization is exhausted; no further write or publication is authorized. See [Current State](./CURRENT_STATE.md).

## Phase 2D.3P - Final Site Map Navigation Execution (2026-10-23)

- The owner's Phase 2D.3P request authorized at most one existing-row Site Map PATCH and no other writes. The existing navigation-only runner was used without redesign or code changes. Its legacy Phase 2D.3N confirmation string remained the local guard contract; the authorization reference explicitly identified the new Phase 2D.3P request.
- Approved target values were loaded from the [reference-table runbook](./PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md) into one short-lived process without printing them. The unique PAC list match and active GUID Environment ID from `pac org who` agreed with the approved target; PAC/Az/WhoAmI identity agreement and the post-agreement user pin passed. No login or environment switch occurred.
- Initial and fresh pre-dispatch snapshots verified the unmanaged Solution/Publisher, exact Active/Unpublished app, direct Site Map association, two approved roles, and exactly 13 components: Site Map 1, entity roots 4, Main forms 4, public views 4, other 0. Roots resolved exactly once to `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc`. Approved forms/views were checked by exact asset identity and parent table.
- Initial, fresh pre-PATCH, and final Web API ValidateApp reads all passed: `ValidationSuccess=true`, zero issues/errors/warnings. This execution retained parsed validation evidence; it did not repeat the Phase 2D.3O raw-response/SDK diagnostic.
- Original navigation was Area1 / Group1 / Subarea1 with no entity target. A final immediate GET confirmed the existing Site Map identity, placeholder XML, and fresh ETag. The PATCH body contained only `sitemapxml`; `If-Match` used that fresh ETag. Exact XML/semantic fingerprints and the one-write guard were checked before dispatch.
- PATCH was attempted once and returned **HTTP 204** with no error. The request identifier was retained as a SHA-256 alias in session evidence; no correlation identifier was returned. There was no HTTP 412 or retry.
- GET-only reconciliation verified the unpublished draft exactly matches Settings / Administration with TA Directory, Positions, Candidate Sources, and Locations pointing respectively to the four approved tables. Published Site Map XML remained unchanged. XML validity, unique navigation, unrelated XML preservation, exact components/roots/assets, roles, app identity, and Active/Unpublished state passed. Outcome: **`VERIFIED_REFERENCE_NAVIGATION_UNPUBLISHED`**.

| Retained fingerprint | SHA-256 |
| --- | --- |
| Original XML | `2bfcfde1f87b6be50867ab0faa5c4be2e736c86538369ab61cbd1d28c909319a` |
| Transformed XML | `923b9572fafe98a089621ac7f23db829ddd5ed9407653949b6421b7bb1c47e8f` |
| Semantic navigation | `f6731270a6ef024501ea94d1692efbabcea8a18eff7225ab3a2b50024afeca2c` |
| Fresh ETag (hash only) | `944402ededb490df661e042bc81ba5b81ba4b81b270c8fc53ff2de1d45964ae4` |

- Phase 2D.3P script-dispatched counts: **109 GET**, including **3 Web API ValidateApp**; **1 Site Map PATCH**; **0 AddAppComponents**, **0 RemoveAppComponents**, **0 other writes**, **0 PublishXml**, **0 app publish**, **0 role changes**, **0 retries**, and **0 SDK Execute**. PAC checks/solution-export traffic is outside the script's request counter.
- Before and after execution: **329** app assertions, **550** provisioning assertions, **11** readiness assertions, **7** PowerShell files parsed without errors, and `git diff --check` passed. The app suite includes transform, duplicate-ID, preservation, ETag/If-Match, 412/no-retry, and final-navigation reconciliation coverage.
- Branch `main`, HEAD and `origin/main` remained `e0251ca8d72fda4c2e901c4ca09b12bb6de725da`. Four pre-existing modified files were preserved; this phase only updates this runbook and Current State. No commit or push occurred.
- **Next task:** owner read-only review and a separately scoped publication/acceptance preflight. Do not rerun the write runner: its placeholder precondition no longer describes the new draft. Do not publish without explicit authorization. Broader Phase 2D completion and business acceptance remain unproven; historical Phase 2D.3N attribution remains unknown.

## Phase 2D.3O — Resumed Read-Only Evidence (2026-10-23)

- Approved URL/organization/environment evidence came from the [reference-table runbook](./PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md) into short-lived process state only. The active GUID Environment ID came from `pac org who`, not the PAC list's non-GUID `EnvironmentIdentifier`. The unique PAC list match, PAC/Az/WhoAmI identities, and expected-user process pin passed without sign-in or environment switching.
- Fresh direct counts were Site Map **1**, entity **4**, form **4**, view **4**, other **0**, total **13**. Root identity and direct association checks passed for `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc`. The approved unmanaged Solution/Publisher, existing app identity, Active/Unpublished state, Main forms, public views, and two existing app-role associations passed.
- Raw Web API ValidateApp: HTTP **200**, `application/json; odata.metadata=minimal`, body present, SHA-256 `1c4c383f4b2f6efdf3e8d47f86d62e5186688846d193dc4c55d9b64501ea1a24`, top-level `@odata.context` and `AppValidationResponse`, Boolean `ValidationSuccess=true`, array `ValidationIssueList=[]`. Issue/error/warning counts were **0/0/0**. Current parser comparisons all matched; no exception or first failing predicate existed.
- SDK cross-check: **one** guarded `ValidateAppRequest` Execute, `MaxRetryCount=0`, `ValidateAppResponse`, success, **0/0/0** issues/errors/warnings. No repeat SDK Execute occurred.
- Fresh evidence exposed unsupported `StatusCodeVariable`/`ResponseHeadersVariable` parameters on raw `Invoke-WebRequest` capture. Their local binding failure sent no HTTP request. The fix uses the returned response status/headers; tests exercise a realistic WebRequest signature, HTTP 200/401, raw-body clearing, and pre-dispatch failure counting. The existing diagnostic/final-navigation snapshot branch also left normalized components empty; both modes now call the existing identity-guarded normalizer, and the final read-only preflight passes.
- Counts across the continuation: **99 script-dispatched Dataverse GET** = 31 initial + 32 completed Web API read run + 36 final inventory/readiness run; **1 Web API ValidateApp**, **1 SDK ValidateApp Execute**, **0 AddAppComponents**, **0 RemoveAppComponents**, **0 Site Map PATCH**, **0 other writes**, **0 PublishXml**, **0 app publish**, **0 role changes**, **0 retries of dispatched requests**. The first uncorrected counter included one local binding failure and must not be treated as wire-request evidence. PAC checks and SDK initialization/discovery are outside this GET counter. One local wrapper syntax error also stopped before any request.
- The historical parser from commit `618d782` was replayed offline against a projection of the retained clean validation fields, not the unavailable Phase 2D.3N body. It produced zero issues and no warning-gate failure after supplying the verified normalized inventory. The former null-issue suspicion is **not reproduced** for this response shape. Current clean results alone do not prove the historical stop was transient or identify its exact predicate. Primary outcome: **`BLOCKED_DIAGNOSTIC_UNKNOWN`**.
- The current Site Map identity/direct association, placeholder XML, fresh ETag, unchanged source XML, and local semantic transform passed. The full final-navigation preflight passed without warning override being needed (zero warnings). Proposed navigation is Settings / Administration → TA Directory, Positions, Candidate Sources, Locations. Secondary result: **`READY_FOR_SITEMAP_PATCH_RETRY`**. No PATCH was sent; a later authorization must acquire fresh state and ETag.
- Branch `main`, HEAD and `origin/main`: `e0251ca8d72fda4c2e901c4ca09b12bb6de725da`; initial worktree clean. No commit or push. Final validation: **329** synthetic app-composition assertions, **550** provisioning assertions, **11** readiness assertions, PowerShell parser validation, and `git diff --check` (see latest executed results).
- **Next task:** owner review of clean present-day validation and unknown historical attribution. Any Site Map write remains a separately authorized operation; keep `srapp` unpublished.

## Phase 2D.3O — ValidateApp Gate Diagnostic (2026-10-23)

The local `-ValidateAppDiagnosticOnly` path is implemented as a read-only diagnostic. It first uses the existing fresh target snapshot with ValidateApp parsing skipped, then captures one raw Web API ValidateApp response before parsing and performs one independent SDK `ValidateAppRequest` Execute through the existing guarded caller-token ServiceClient with `MaxRetryCount=0`. Sanitized diagnostics retain HTTP status, content type, body-present flag and SHA-256, JSON property names, supported response-shape flags, validation result, issue/error/warning counts and safe issue summaries, parser stage, first failing predicate, and sanitized exception details. The raw response body is not emitted.

- Synthetic coverage includes clean, warning-only, blocked, missing-property, wrong-type, malformed JSON, HTTP 401/403/429/5xx, transport exception retention, raw/local comparison, SDK result summary, and conservative final classification cases. It also verifies the diagnostic mode blocks writes and raw capture outside the guarded ValidateApp path.
- The former local issue-list extraction could flatten an empty JSON array into a null placeholder and count it as an issue. That parsing defect is fixed and regression-tested. It is not confirmed as the Phase 2D.3N root cause because the prior run did not retain its raw response or failing predicate.
- The live diagnostic was **not run**. The current process lacks `BSO_RS_ENVIRONMENT_NAME`, `BSO_RS_ORG_URL`, `BSO_RS_EXPECTED_ENVIRONMENT_ID`, and `BSO_RS_EXPECTED_ORG_ID`. No PAC/Az identity call, Dataverse GET, SDK Execute, write, publish, role change, retry, environment switch, or interactive login occurred. Phase classification is **`BLOCKED_DIAGNOSTIC_UNKNOWN`** because the preflight could not start; there is no live validation result.
- Local checks passed **324** app-composition assertions, **550** provisioning assertions, **11** readiness assertions, PowerShell parser validation (**0 errors**), and `git diff --check`. Branch `main`, HEAD and `origin/main` are `618d7825fdb1487182f76449d6cd11e4c34e6dc8`; no commit or push occurred.
- **Next task:** set the approved four target guard values in the intended PowerShell process, then run the same guarded GET-only diagnostic. Do not use an alternate connection path or infer the prior live result.

## Phase 2D.3N — Final Site Map Navigation (2026-10-23)

The approved scope allowed at most one PATCH to the existing Site Map, with a fresh ETag in `If-Match` and a request body containing only `sitemapxml`. The dedicated `-FinalSiteMapNavigationOnly` path and synthetic tests were implemented, including exact component/root/form/view/role checks, placeholder navigation and XML-preservation checks, a zero-warning pre-PATCH ValidateApp guard, an immediate Site Map/ETag GET, and GET-only reconciliation. The code and test changes remain uncommitted.

- The read-only PAC environment checks matched the approved VN LMV IT target. The guarded Dataverse run made 32 GET requests and stopped at the current app dependency-validation stage with `FAILED_VALIDATION`.
- The safe runner output omitted the underlying dependency-validation response, so it is not known whether this was an HTTP/API failure, a response-shape issue, or a validation condition. No ValidateApp issue count or content is asserted.
- No Site Map PATCH or other write was sent; no post-PATCH reconciliation occurred. The app/navigation state was not changed by this attempt, but no post-attempt GET independently reconfirmed live state.
- Local regression validation passed **294** app-composition assertions, **550** provisioning assertions, **11** readiness assertions, PowerShell parser validation (**0 errors**), and `git diff --check`. Git remained on `main` at `885abd496c066444464e5898ac89bf2abd97c0eb`, matching `origin/main`. No commit or push occurred.
- **Next step:** perform a bounded GET-only diagnosis of the stopped dependency-validation stage and retain sanitized status/error/ValidateApp evidence. Do not retry PATCH until the cause is understood and every fresh environment, identity, composition, protected-state, XML, and ValidateApp gate passes.

## Phase 2D.3M — Remaining Table Roots (2026-10-23)

The authorized scope was exactly one SDK `AddAppComponentsRequest` containing Position (`os_sr_pos`), Candidate Source (`os_sr_csrc`), and Location (`os_sr_loc`) references, each paired with its freshly verified `EntityMetadata.MetadataId`. No raw Web API Add, Remove, Site Map patch, other write, publish, role change, or retry was permitted.

- The corrected fresh guarded preflight verified the approved VN LMV IT environment, PAC/Az/Dataverse identities, expected-user process pin, unmanaged Solution `os_sr_bso_rs_support`, Publisher `os_bso_rs_support` with prefix `os`, exact existing `srapp`, Active/Unpublished state, existing Site Map association, protected components and roles, and the exact 10-component starting inventory. The active PAC Environment ID was read from `pac org who`; the unique environment-list entry independently matched the approved name, organization URL, and organization ID.
- The starting direct inventory was one Site Map, one `os_sr_ta` entity root, four forms, and four views. Fresh reads verified each requested table's `EntityDefinitions.MetadataId` against `/entities.entityid`, valid object type codes, and distinct IDs from system `entity`.
- The SDK request contained exactly three `EntityReference` objects, with logical names `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc` and their respective verified MetadataIds. It targeted the existing `srapp` AppId. Normalized request fingerprint: `964c2629edc1f17fcb95a5d240e096cdad7610d4821855249b7614a8d64c7d16`. The single SDK Execute succeeded as `AddAppComponentsResponse`; the SDK response did not expose an HTTP status.
- GET-only reconciliation verified the final 13-component inventory: one Site Map, four entity roots, four forms, and four views. The four roots resolve exactly once to `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc`; each object ID resolved to its expected entity identity and app association. No other direct component was present.
- The Site Map identity and placeholder navigation XML, all four approved forms and views, System Administrator and System Customizer roles, and Active/Unpublished `srapp` state remained unchanged. `ValidateApp` succeeded with zero blocking errors and zero warnings. No navigation PATCH or publication occurred.
- Final counts: **171 Dataverse GET**, **0 raw AddAppComponents POST**, **1 SDK AddAppComponents Execute**, **0 RemoveAppComponents POST**, **0 Site Map PATCH**, **0 other writes**, **0 PublishXml**, **0 app publish**, **0 role changes**, and **0 retries**. A preliminary invocation stopped before Dataverse access after the local wrapper supplied a non-GUID PAC `EnvironmentIdentifier`; it made **0 GET and 0 writes**. The corrected runner derived the expected active Environment ID from `pac org who` and independently matched the unique PAC list entry on approved name, URL, and organization ID.
- Regression validation passed **264** app-composition assertions, **550** provisioning assertions, **11** readiness assertions, parser validation (**0 errors**), and `git diff --check`. Branch `main`, HEAD and `origin/main` remained `dec0a784ce5a738e7c379f446287bf1ff6bc9e02`. No commit or push occurred.
- **Next task:** seek separate bounded authorization for a fresh-guarded Site Map navigation update from the approved navigation design. Keep the app unpublished; do not change roles or add components without separate authorization.

## Phase 2D.3L — Correct LogicalName SDK Canary

The approved sequence was one logical removal of the confirmed system `entity` component, exact GET-only reconciliation to nine protected components, then at most one SDK Add using the TA table's actual logical name and freshly retrieved `EntityMetadata.MetadataId`. It was not a multi-table composition or navigation update.

- The PAC environment list contained exactly one VN LMV IT entry at the approved organization URL, and `pac org who` matched it. The guarded runner verified PAC identity, existing Az identity, Dataverse WhoAmI, and the expected-user process pin. No interactive login or environment switch occurred.
- The fresh starting inventory was one Site Map, one wrong system `entity` root, four approved Main forms, and four approved public views. Exactly one `RemoveAppComponents` POST was dispatched; it returned HTTP 204. GET-only reconciliation then confirmed the exact interim inventory: one Site Map, zero entity roots, four forms, four views, zero other direct components. Protected components and roles were unchanged.
- The remove payload was one typed system `entity` component and its fingerprint was revalidated immediately before dispatch. The fingerprint itself was not retained by the sanitized execution summary, so no value is asserted here.
- Fresh TA and system metadata reads verified `EntityDefinitions.MetadataId` against `/entities.entityid` for both logical names, validated their object type codes, and confirmed that TA's metadata ID differs from system `entity`. The SDK request contained exactly one component: `EntityReference("os_sr_ta", TA_MetadataId)`. The normalized SDK request fingerprint was `b58ee28352aa3e562b299c3f7b1683dce7df51782e2e2ebfb823649b41efabdb`.
- SDK Execute succeeded. Final direct inventory is one Site Map, one entity root, four forms, four views, and zero other components. The new root resolves to `os_sr_ta`, its entity ID matches the queried object ID, and its direct app association matches. The exact outcome is **`CORRECT_LOGICALNAME_CANARY_VERIFIED`**.
- The Site Map identity and placeholder XML/navigation, four approved forms, four approved public views, System Administrator and System Customizer roles, and Active/Unpublished `srapp` state remained unchanged. `ValidateApp` succeeded with zero blocking errors and six warnings, a reduction of three from the preceding nine-warning baseline. Per-warning `RequiredComponents` were not retained, so the specific TA warning entries resolved are not identified.
- Final guarded-runner counts: **229 Dataverse GET**, **1 RemoveAppComponents POST** (HTTP 204), **0 raw AddAppComponents POST**, **1 SDK AddAppComponents Execute**, **0 Site Map PATCH**, **0 other writes**, **0 PublishXml**, **0 app publish**, **0 role changes**, **0 retries**. The PAC environment listing and `pac org who` prechecks were separate read-only CLI checks and are not included in the Dataverse GET count.
- Regression validation passed **232** app-composition assertions, **550** provisioning assertions, **11** readiness assertions, PowerShell parser validation (**0 errors**), and `git diff --check`. Branch `main`, HEAD and `origin/main` remained `1574b6e4381e8f895a17c5f27967d20015a8c063`; no commit or push occurred.
- Recommended next task: obtain separate bounded authorization for a fresh-guarded addition of the remaining approved table roots (`os_sr_pos`, `os_sr_csrc`, and `os_sr_loc`), each using its actual logical name and freshly verified `EntityMetadata.MetadataId`. Preserve the verified TA root and protected components. Do not patch navigation, publish, or change roles as part of that next step unless separately authorized.

## Historical — Phase 2D.3K — Single Wrong-Root Removal and SDK TA Canary

The approved sequence was one logical removal of the confirmed system `entity` component, exact GET-only reconciliation to nine protected components, then at most one SDK `AddAppComponentsRequest` Execute for the TA table. It was not a successful TA-root composition.

- The fresh guarded preflight confirmed the expected target identities, Solution/Publisher, `srapp` identity and Active/Unpublished state, direct Site Map association, expected roles, and exactly one wrong system `entity` root. The exact removal envelope contained one system `entity` component and had fingerprint `73b431f524303ff55c73fbeab864f6c71fc46debba5aa46bba5d4ed70ff54aae`. The POST returned HTTP 204.
- GET-only reconciliation after removal verified one Site Map, zero entity roots, four approved Main forms, four approved public views, and zero other direct components. `ValidateApp` had zero blocking errors; its nine warnings were the eight unresolved table dependencies plus the no-entity-reference warning. Protected state and roles were unchanged.
- The caller-token ServiceClient was verified ready for the guarded organization with zero retries. A single SDK request used `Microsoft.Crm.Sdk.Messages.AddAppComponentsRequest`, an `EntityReferenceCollection` of count one, logical name `entity`, the freshly resolved TA `entityid`, and the existing `srapp` AppId. Its normalized request fingerprint was `d750831dd865644dec74fa190aa794d68a6999bade9bb8388e4dee0b41d13065`. SDK Execute returned `AddAppComponentsResponse`; no HTTP status or SDK error was exposed.
- Final GET-only reconciliation found one direct type-1 root resolving to logical name `entity`, rather than `os_sr_ta`. Final inventory: one Site Map, one wrong system root, four forms, four views, zero other components. The Site Map placeholder was unchanged, `srapp` remains Active/Unpublished, and role associations are unchanged. Final `ValidateApp` succeeded with zero blocking errors and nine warnings: eight unresolved project-table dependencies and warning `-2147155691`, “Entity doesn’t reference a form or view. App users will see all forms and views.”
- **Outcome: `SDK_WRONG_SYSTEM_ROOT_CREATED`.** The removal was effective, but the SDK Add did not produce the intended TA root. Do not retry or automatically remove the resulting root. The reason for this SDK behavior remains unknown and requires GET-only investigation before any new repair plan.
- Final authorized runner counts: **225 GET**, **1 RemoveAppComponents POST** (HTTP 204), **0 raw AddAppComponents POST**, **1 SDK AddAppComponents Execute**, **0 Site Map PATCH**, **0 other writes**, **0 PublishXml**, **0 app publish**, **0 role changes**, and **0 retries**. Separate pre-write dependency diagnostics were GET-only and are not included in this runner count.
- The local SDK client initially failed to initialize because matching Microsoft.Extensions dependencies were unavailable. Exact dependency assets were restored into the user NuGet cache; the guarded loader now resolves exact versions from the cache and fails closed on missing or mismatched assets. No repository dependency manifest was changed.
- Regression validation passed **227** app-composition assertions, **550** provisioning/recovery assertions, **11** readiness assertions, PowerShell parser validation (**0 errors**), and `git diff --check`. Branch `main`, HEAD and `origin/main` remained `7db28a4b2f8d3964bc2fb709e977cfff0612f23e`; no commit or push occurred.
- Recommended next task: GET-only investigation of the SDK AddAppComponents identity behavior. Any new Remove/Add action requires explicit authorization and fresh guarded preflight; do not patch navigation or publish.

**Current status — Phase 2D.3J forensic investigation:** Fresh guarded, GET-only inspection confirmed the approved target and identity guards, the existing Active/Unpublished `srapp`, and the same direct inventory as Phase 2D.3I: one Site Map, one type-1 root resolving to system logical name `entity`, four approved Main forms, and four approved public views. `ValidateApp` returned zero blocking errors and nine warnings. Live `$metadata` identifies `AddAppComponents` as accepting `AppId: Edm.Guid` and `Components: Collection(mscrm.crmbaseentity)`; `Microsoft.Dynamics.CRM.entity` has `entityid: Edm.Guid` as key and uses entity set `entities`. The local forensic reconstruction retained the TA `entityid` as a string through component construction and serialization, while noting that the canary uses JSON depth 10 and the existing path uses depth 30. A local SDK `AddAppComponentsRequest` with one `EntityReference("entity", <TA entityid>)` was constructed from already-cached PAC CLI assemblies; it was not executed. The historical 2D.3I request body was not captured, so the current reconstruction cannot establish what was sent then. A raw-Web-API identity issue is a hypothesis, not a proven cause. Recommendation: **`SDK_PIVOT_RECOMMENDED`**, pending separate explicit write authorization. Phase 2D.3J counts: **76 GET**, **0 AddAppComponents POST**, **0 RemoveAppComponents POST**, **0 Site Map PATCH**, **0 other POST**, **0 SDK Execute**, **0 PublishXml**, **0 app publish**, **0 role changes**, and **0 retries**. No repair, navigation change, publication, or retry is authorized. See [Current State](./CURRENT_STATE.md).

## Phase 2D.3J — AddAppComponents Contract Forensics (GET-Only)

The purpose of this phase was to investigate the repeated wrong system `entity` root using fresh guarded reads, live `$metadata`, local request reconstruction, and local SDK construction. No Dataverse write or SDK execution was authorized or performed.

- Two guarded live read runs completed with **38 GET** each. Target, PAC/Az/Dataverse identity, expected-user, Solution/Publisher, `srapp`, app status, Site Map, roles, and component-inventory gates passed. The current app remains Active/Unpublished; its existing Site Map and protected forms/views remain unchanged.
- The current direct inventory remains one Site Map, one type-1 component resolving through `appmodulecomponent.objectid` → `entities.entityid` to logical name `entity`, four approved forms, and four approved views. `ValidateApp` reports zero blocking errors and nine warnings. The approved TA table root is still not represented.
- Live `$metadata` confirms `AddAppComponents(AppId: Edm.Guid, Components: Collection(mscrm.crmbaseentity))`; type `Microsoft.Dynamics.CRM.entity` has key `entityid: Edm.Guid` and entity set `entities`. Microsoft's [`AddAppComponents` Web API reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/addappcomponents) documents the base-entity collection but does not show a table-root request example. The SDK [`Components` property reference](https://learn.microsoft.com/en-us/dotnet/api/microsoft.crm.sdk.messages.addappcomponentsrequest.components?view=dataverse-sdk-latest) documents `EntityReferenceCollection`.
- Current-path reconstruction verifies one typed entity component and matching TA identity through the component, wrapper, and serialized JSON stages. Its semantic fingerprint is `ff53ed8ce44ed720e5b10b9a9dac7281f850e2838273f83275344dee6146ed5b`; serialized-body SHA-256 is `3e7af353699dbeb11af1c02cf28a7665d4843cb19c726ed5092284be566a3618`. These values apply only to the reconstructed current request. Phase 2D.3I's dispatched body and fingerprints were not retained and remain **NOT VERIFIABLE**.
- Entity, form, and view components share the same ordered-dictionary construction, property ordering, string identity representation, and no custom converter. The canary serializer uses JSON depth 10; the existing general path uses depth 30. This difference is documented for evaluation; the simple inspected identity fields remained strings in the reconstructed JSON.
- Using SDK assemblies already in the PAC CLI package cache (no package installation), the local diagnostic successfully constructed an `AddAppComponentsRequest` whose `Components` property contains an `EntityReferenceCollection` with one `EntityReference("entity", <TA entityid>)`, and whose AppId matches `srapp`. The local assembly versions were Dataverse.Client 1.2.0.0, Crm.Sdk.Proxy 9.0.0.0, and Xrm.Sdk 9.0.0.0; the PAC CLI bundle version was 2.13.1. The diagnostic did not connect a client or call `Execute`.
- Forensic classification: **`CONTRACTS_SEMANTICALLY_EQUIVALENT`** for the currently reconstructed request shapes; **`RAW_WEBAPI_ENTITY_REFERENCE_UNTRUSTED`** is a working risk classification, not an established cause. Decision: **`SDK_PIVOT_RECOMMENDED`**. Any SDK canary requires a new, separately authorized bounded task and fresh guarded preflight.
- Outcome: **`READ_ONLY_FORENSICS_COMPLETE`**. Counts for the complete Phase 2D.3J continuation: **76 GET**, **0 AddAppComponents POST**, **0 RemoveAppComponents POST**, **0 Site Map PATCH**, **0 other POST**, **0 SDK Execute**, **0 PublishXml**, **0 app publish**, **0 role changes**, and **0 retries**. The branch/HEAD remained unchanged; the script and test changes are uncommitted. No environment switch, package installation, commit, or push occurred.
- Git baseline: branch `main`; HEAD and `origin/main` both `c44d022e7a243dc1b885251bdf7981f97aa84d86`. The four uncommitted files are [current status](./CURRENT_STATE.md), [automation script](../scripts/Configure-BsoRsModelDrivenApp.ps1), [composition tests](../tests/ModelDrivenAppComposition.Tests.ps1), and this runbook.
- Regression checks passed: **204** app-composition assertions, **550** provisioning/recovery assertions, **11** readiness assertions, PowerShell parser validation, and `git diff --check`.
- This phase supersedes the Phase 2D.3I recommendation to investigate the request contract. Do not remove/add components, patch the Site Map, or publish until a subsequent explicitly authorized phase.

**Historical snapshot:** The Phase 2D.3I status paragraph below describes that earlier checkpoint and is superseded by Phase 2D.3J above.
**Current status — Phase 2D.3I TA entity canary:** The owner-authorized attempt dispatched one `AddAppComponents` POST after the guarded preflight. The runner stopped with exit code 1 and did not preserve a reliable HTTP status, response/correlation IDs, or the canary payload fingerprints. Do not retry. Two subsequent GET-only diagnostics each completed with 38 GETs and no writes. They verified ten direct components: one existing Site Map, one entity root, four approved Information Main forms, and four approved public views. The sole entity root resolves through `appmodulecomponent.objectid` → `entities.entityid` to system logical name `entity`, not `os_sr_ta`; the approved table identities themselves resolve consistently. `srapp` remains Active/Unpublished; the placeholder Site Map and direct association, forms/views, and System Administrator/System Customizer roles are unchanged. `ValidateApp` succeeds with zero blocking errors and nine warnings (eight unresolved table references and the existing non-blocking entity/form-or-view warning). Outcome: **`WRONG_SYSTEM_ENTITY_ROOT_RECREATED`**. Combined Web API counts: **150 GET**, **1 AddAppComponents POST**, **0 other POST**, **0 PATCH**, **0 PublishXml**, **0 app publish**, **0 role changes**, **0 retries**. No repair, navigation change, or publication is authorized by this result. Next: perform a separately authorized read-only investigation of the AddAppComponents component identity contract and the dispatched request evidence; only then plan a separately authorized repair. See [Current State](./CURRENT_STATE.md).

**Superseded Phase 2D.3F/3G status — 23 October 2026:** Phase 2D.3C's **LIVE_STATE_INCONSISTENCY** conclusion is withdrawn as unsupported because it compared unlike identifiers. The required type-1 identity chain is `appmodulecomponent.objectid` → `entities?$filter=entityid eq <guid>` → `logicalname`; `appmodulecomponentid` is a separate record ID and must not be compared with `EntityDefinitions.MetadataId`. Phase 2D.3G confirmed the four roots were the system `entity` table, not approved project tables. Phase 2D.3H's bounded removal result below supersedes the prior 13-component state and the instruction not to remove.

**Current status — Phase 2D.3H:** One authorized RemoveAppComponents POST for exactly one typed system `entity` component returned HTTP 204. Fresh GET-only reconciliation verified the intended interim inventory: one existing Site Map, zero entity roots, four approved Main forms, four approved public views, and zero other components. The Site Map remains unchanged and directly associated, the four forms/views remain present, roles remain System Administrator/System Customizer, and `srapp` remains Active/Unpublished. `ValidateApp` succeeds with zero blockers and nine warnings caused by the intentionally absent table roots. Outcome: `WRONG_ROOTS_FULLY_REMOVED`. Counts across the attempt and all read-only reconciliation: 166 GET, one RemoveAppComponents POST, all other writes and retries zero. The cause of the original wrong roots remains unknown. Do not add components or patch navigation without a separate authorization and fresh preflight. See [Current State](./CURRENT_STATE.md).

**Historical adoption status — 21 October 2026:** The owner adopted the existing BSO-RS-Support AppModule `srapp` (ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`) in `os_sr_bso_rs_support`. The actual unique name is `srapp`; `os_srapp` is superseded and must not be used or applied by renaming.

The dated adoption-status paragraph below records the pre-Phase 2D.1 state and is superseded by this current status and the Phase 2D.2 result.

**Superseded status — Phase 2D.3G:** Two fresh guarded GET-only diagnostics confirmed that the four type-1 AppModule components shared one object ID resolving through `entities.entityid` to system logical name `entity`, not an approved project table. The approved table IDs were independently verified through both `EntityDefinitions.MetadataId` and `entities.entityid`; the cause of the wrong roots was not established. The repair was ambiguous at that point because RemoveAppComponents duplicate-reference behavior was undocumented. Phase 2D.3H below records the owner-authorized single logical removal and its reconciled result.

## Adopted App Identity

**Superseding update — 22 October 2026:** The owner subsequently authorized the bounded Phase 2D.1 preflight and conditional composition. Fresh `ValidateApp` returned the blocking error `App does not contain Site Map`; the result is **BLOCKED_BEFORE_WRITE**. No write was attempted. The Phase 2D plan below is historical and is superseded where it conflicts with the findings and open decision recorded in Phase 2D.1.

- Environment: VN LMV IT, `https://org14938ec2.crm4.dynamics.com/`.
- App: BSO-RS-Support, unique name `srapp`, AppModule ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`.
- Solution: `os_sr_bso_rs_support`; the AppModule is verified as a type-80 root. The Solution Publisher is `os_bso_rs_support`; the AppModule Publisher lookup remains **UNKNOWN**.
- Phase 2C closed by owner-approved adoption, not by a successful AppModule Create. No additional AppModule is required. Do not create, rename, or recreate the app.
- R3-P GET-only DryRun reconfirmed `statecode=0` Active and `componentstate=1` Unpublished. The `srapp` Site Map remains Published with placeholder-only XML; the Site Map unpublished query returned `componentstate=0`, so no distinct draft layer was observed. The target Solution export contains one `AppModuleSiteMap.SiteMapUniqueName=srapp` binding; direct appmodulecomponents remains empty. No verified app-linked forms/views/pages or project-specific end-user role were found. System Administrator and System Customizer are the only verified app-role associations. Type 10091 remains unidentified and is not the type-62 Site Map object.

## Phase 2D.2 — Existing Site Map Association

The owner authorized exactly one bounded `AddAppComponents` call containing only the live-resolved existing Site Map. No Site Map XML PATCH, publication, role change, reference-table component, or app identity change was in scope.

- Fresh identity and environment guards matched VN LMV IT; the expected-user guard was configured in process scope only after PAC, Az, and Dataverse WhoAmI identity agreement.
- The Solution export binding and exact live Site Map identity matched. The Site Map was already present in the Solution; the Solution contained exactly one intended type-62 root. Pre-write direct AppModule components were empty.
- Pre-write `ValidateApp` returned the exact blocker `App does not contain Site Map`, with warnings `No component is referenced` and `App does not reference at least one entity`.
- The request contained the existing `srapp` AppId and exactly one typed `Microsoft.Dynamics.CRM.sitemap` component with the verified `sitemapid`. The single POST returned HTTP 204.
- GET-only reconciliation verified the direct Site Map component, no other direct app components, unchanged app identity and Active/Unpublished state, unchanged Site Map ID/XML/publication state, and unchanged managed role associations. Post-write `ValidateApp` no longer reports the Site Map error; the warning `App does not reference at least one entity` remains because no table/form/view components were authorized here.
- **Outcome: VERIFIED_SITEMAP_ASSOCIATED.** Counts: **75 Dataverse Web API GET**, **1 AddAppComponents POST** (HTTP 204), **0 other POST**, **0 Site Map PATCH**, **0 PublishXml**, **0 publish operation**, **0 role change**, and **0 retry**. The GET count is the script’s recorded Web API counter and excludes separate PAC identity and read-only Solution-export CLI operations.
- At the time, stop after this association. The owner later separately authorized Phase 2D.3; its current preflight outcome is recorded below.

## Phase 2D.3A — Authorized Reference UI Dry Run (Ready)

The owner authorized one `AddAppComponents` operation for exactly the four approved reference tables, their Information Main forms, and their public active views, followed only after reconciliation and intermediate `ValidateApp` by at most one ETag-protected PATCH of the existing Site Map. Publishing, role changes, other components, table changes, retries, and app recreation are outside scope.

- Local automation resolves exact component names and states, verifies each table's Solution root and confirms exact form/view IDs in a read-only Solution export, requires the existing Site Map as the only initial direct app component, and validates the expected System Administrator/System Customizer associations. It refuses to patch navigation until all 12 requested app components reconcile exactly and the intermediate entity-reference warning is gone.
- The request order is POST `AddAppComponents` (exactly 12 components) first, then PATCH `sitemapxml` on the existing Site Map with `If-Match`; operation counts are guarded to one each and retries are disabled. GET-only reconciliation checks the 13 direct app components, navigation XML, unchanged roles, app identity, and unpublished state. No publish endpoint is implemented in this mode.
- The successful fresh dry run restored the approved target guards in a short-lived process, matched PAC/Az/WhoAmI identities, then process-pinned the verified Dataverse user identity. No interactive login or environment switch occurred. The unmanaged Solution `os_sr_bso_rs_support`, Publisher `os_bso_rs_support`, and prefix `os` matched.
- Exact draft retrieval verified existing BSO-RS-Support AppModule `srapp` as Active/Unpublished. The published `appmodules` collection returned zero matching rows, which was not treated as absence; exactly one AppModule type-80 root exists in the target Solution. The app-aware `srapp` Site Map is Published, has one type-62 Solution root and one `AppModuleSiteMap` binding, remains directly associated with the app, and has a usable ETag.
- Fresh resolution found exactly `os_sr_ta` / Information / Active TA Directories; `os_sr_pos` / Information / Active Positions; `os_sr_csrc` / Information / Active Candidate Sources; and `os_sr_loc` / Information / Active Locations. Tables, forms, and views are active; the views are public. The payload is exactly 12 distinct components (4 entity, 4 systemform, 4 savedquery), excludes the Site Map and unrelated component types, and has normalized SHA-256 `ac66583cc589e1da351cf95025e3a902d8aa54484e9e68f1ba10ee6569269a50`.
- The Site Map semantic delta preserves the existing placeholder navigation identities and changes the navigation to Settings > Administration > TA Directory (`os_sr_ta`), Positions (`os_sr_pos`), Candidate Sources (`os_sr_csrc`), and Locations (`os_sr_loc`). `ValidateApp` succeeds with the single non-blocking warning `App does not reference at least one entity`; the Site Map blocker and all blocking errors are absent.
- **Outcome: READY_FOR_REFERENCE_UI_EXECUTION.** The successful dry run issued **27 Dataverse Web API GET**, **0 AddAppComponents POST**, **0 Site Map PATCH**, **0 other POST**, **0 PublishXml**, **0 app publish**, **0 role change**, and **0 retry**. Across all guarded runs and focused diagnostics in the Phase 2D.3A continuation, the cumulative Web API count is **138 GET** and all write counts remain zero. Five PAC Solution exports were read-only CLI operations and are excluded from that Web API counter.
- Regression validation at the dry-run checkpoint passed: **89** app-composition assertions, **550** provisioning/recovery assertions, **11** readiness assertions, and `git diff --check`. The execution outcome is recorded in the following Phase 2D.3B section.

## Phase 2D.3B — Reference Components Added; Site Map Not Updated (Partial State)

- The short-lived Apply process restored the approved target guards from the authoritative runbook and matched PAC, existing Az, and Dataverse WhoAmI identities before setting the expected-user process pin. The fresh preflight verified the exact Solution/Publisher/prefix, existing AppModule identity and Active/Unpublished state, existing Site Map association, unchanged approved role set, and no pre-existing reference table/form/view components.
- The fresh 12-component payload matched the approved SHA-256 `ac66583cc589e1da351cf95025e3a902d8aa54484e9e68f1ba10ee6569269a50`. Exactly one AddAppComponents POST was sent. The execution proceeded to GET reconciliation, which establishes a 2xx outcome; the exact HTTP status was not retained in the sanitized summary.
- GET-only reconciliation confirmed exactly 13 direct components: one existing Site Map, four entities, four Main forms, and four public views. The app remains BSO-RS-Support / `srapp`, Active/Unpublished. Role associations remain System Administrator and System Customizer.
- The controller stopped at a pre-PATCH integrity gate. Its sanitized exception report did not retain the exact failed local predicate. Therefore, the existing Site Map was not patched and the user-authorized one-PATCH maximum remains unused; no attempt was made to bypass or re-evaluate the failed gate by writing.
- The Site Map remains Published with the placeholder Area/Group/SubArea. `ValidateApp` currently succeeds with zero blocking errors and nine warnings: eight entries have empty Message and CRM error code `0`; one says “Entity doesn’t reference a form or view. App users will see all forms and views.” Neither `App does not contain Site Map` nor `App does not reference at least one entity` appears.
- **Outcome: PARTIAL_STATE.** Current task counts, including the subsequent GET-only reconciliation and warning-field inspection: **110 Dataverse Web API GET**, **1 AddAppComponents POST** (2xx; exact status not retained), **0 Site Map PATCH**, **0 other POST**, **0 PublishXml**, **0 app publish**, **0 role changes**, and **0 retries**. Four PAC Solution exports were read-only CLI operations and are excluded from the Web API count.
- Offline regression validation after the operation passed **91** app-composition assertions, **550** provisioning/recovery assertions, **11** readiness assertions, and `git diff --check`. The local implementation now checks the exact payload fingerprint before POST and, if the PATCH gate is reached in a future authorized run, uses the freshly reread ETag.

## Phase 2D.3D — Corrected Identity Model; Live PATCH Not Executed

The corrected evidence model resolves each direct type-1 `appmodulecomponent.objectid` against `entities.entityid` and compares the resolved `logicalname` to the four approved table names. `appmodulecomponentid` identifies the component record, while `EntityDefinitions.MetadataId` belongs to a separate metadata identity surface; comparing either to the type-1 `objectid` is invalid. Root fields may be unknown or empty and are not, by themselves, evidence of a broken entity link.

- The local composition normalizer now applies that identity chain and rejects unresolved, ambiguous, duplicate, or unapproved logical names. The `ValidateApp` summary distinguishes required components resolved by the normalized inventory, unresolved required components, and the non-blocking `-2147155691` form/view-selection warning. `ValidationSuccess=false`, errors, and unresolved required components remain stop conditions.
- The Phase 2D.3D execution mode forbids all POST operations, permits at most one Site Map PATCH, requires exact composed inventory and a fresh pre-PATCH GET snapshot, and uses only the fresh ETag. It does not retry or publish. This describes local code behavior, not a live operation.
- The designated environment URL was not explicitly reconfirmed for this continuation. Consequently, no PAC/Az/WhoAmI checks, Dataverse GET, write, Site Map ETag read, or live reconciliation was performed. Existing 2D.3B/2D.3C observations remain historical only; current direct composition and navigation are **NOT REVERIFIED**.
- Offline regression validation for this code continuation passed **96** synthetic app-composition assertions, **550** provisioning/recovery assertions, **11** readiness assertions, and `git diff --check`. The tests perform no authentication, PAC operation, or Dataverse request.
- **Outcome: BLOCKED_BEFORE_LIVE_PREFLIGHT.** Phase 2D.3D write counts for this continuation: **0 GET**, **0 AddAppComponents POST**, **0 Site Map PATCH**, **0 other POST**, **0 PublishXml**, **0 app publish**, **0 role changes**, and **0 retries**. Do not execute the PATCH-only mode until the designated target is explicitly confirmed and all fresh guards pass. Never repeat AddAppComponents.

## Phase 2D.3D Live Preflight Attempt — Stopped Before Write

The owner confirmed that the previously designated VN LMV IT environment remains the approved target. The guarded process loaded target configuration from the authoritative [Phase 1D-B Reference Table Runbook](./PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md) without printing or persisting raw guard values. It ran the existing PATCH-only path with AddAppComponents forbidden.

- The script passed PAC target comparison, the existing Az user check, Dataverse WhoAmI identity comparison, and the process-scoped expected-user guard before proceeding into Solution/AppModule/Site Map and component reads.
- The preflight stopped at `Verify AppModule entity identity contract` with HTTP 400. The script returned **23 GET** requests, `WritesMayHaveOccurred=false`, and no write results. The response body was omitted; the exact failing subrequest was not established.
- Because the normalized entity identities could not be resolved, no complete exact app-component inventory or role snapshot was accepted. The run did not reach a completed `ValidateApp` gate or a fresh pre-PATCH XML/ETag gate. Do not infer those checks passed from earlier phases.
- **Outcome: BLOCKED_BEFORE_PATCH.** Counts: **23 GET**, **0 AddAppComponents POST**, **0 RemoveAppComponents**, **0 Site Map PATCH**, **0 other POST**, **0 PublishXml**, **0 app publish**, **0 role changes**, and **0 retries**. `srapp` was not published. No commit or push occurred.
- Stop. Do not retry or substitute an unverified identity endpoint. Investigate the HTTP 400 using a separately reviewed read-only approach, then require a new fresh guarded preflight before considering the single Site Map PATCH. AddAppComponents must never be repeated.

## Phase 2D.3E — Collection Resolver Fix; Fresh Run Stopped Before PATCH

The owner supplied the supported entity read pattern: `entities` is a collection that supports RetrieveMultiple, not a single-record GET by `entityid`. The local resolver now builds an encoded collection query selecting `entityid,logicalname,name,objecttypecode` and filtering by the validated `appmodulecomponent.objectid`. It requires exactly one result and stops on zero, multiple, or HTTP failure. No fallback to `EntityDefinitions.MetadataId` equality is used.

- Synthetic tests verify collection-path usage, the `entityid eq <objectid>` filter, all selected fields, one-row resolution, zero/multiple-row failure, HTTP 400 failure, logical-name normalization, no metadata-ID fallback, and GET-only behavior.
- After the owner's VN LMV IT confirmation, the fresh guarded run again passed the target and PAC/Az/WhoAmI identity checks. It then stopped during the `Verify AppModule entity identity contract` stage after **26 GET**. The last HTTP status recorded was 200, `WritesMayHaveOccurred=false`, and no write result was recorded. The sanitized output did not retain which local entity-resolution/normalization predicate failed; therefore this is not evidence of a specific live mismatch or a completed composition.
- The run did not establish exact 13-component composition, unchanged role associations, `ValidateApp`, current Site Map XML, or a fresh ETag. No PATCH was eligible.
- Offline regression validation: **106** synthetic app-composition assertions, **550** provisioning/recovery assertions, **11** readiness assertions, and `git diff --check` passed.
- **Outcome: BLOCKED_BEFORE_PATCH.** Counts: **26 GET**, **0 AddAppComponents POST**, **0 RemoveAppComponents POST**, **0 Site Map PATCH**, **0 other POST**, **0 PublishXml**, **0 app publish**, **0 role changes**, **0 retries**. `srapp` was not published. No commit or push occurred.
- Stop live activity. First improve local sanitized failure classification or diagnose the failed predicate using synthetic fixtures. Any subsequent live run requires a fresh guarded preflight; do not repeat AddAppComponents.

## Phase 2D.3F — Entity Identity Diagnostic; Site Map PATCH Not Eligible

One fresh guarded, GET-only diagnostic completed after a local pre-request failure was traced to the diagnostic mode not being allowed to process-pin the already verified operator identity. The allow-list was extended only for this read-only diagnostic mode and covered by a synthetic regression assertion. Target guards and PAC/Az/Dataverse WhoAmI agreement passed; the expected-user pin was process-scoped and set only after the identities matched.

- The live direct component inventory reported 13 entries: one existing Site Map, four type-1 entity components, four type-60 forms, four type-26 views, and zero other component types. `srapp` was Active/Unpublished; the app-aware Site Map `srapp` had an ETag and remained associated. The observed role names were System Administrator and System Customizer.
- All four type-1 records had valid object IDs and component/app association, and each `entities` collection query returned HTTP 200 with one row whose `entityid` matched the queried object ID. Nevertheless, each row returned `logicalname=entity`; none resolved to the expected table names. The approved-payload entity IDs were absent from the diagnostic projection, so payload-ID equality comparisons were unavailable. The structural identity-contract check passed, but the approved-name check failed with `ENTITY_LOGICALNAME_UNEXPECTED` and aggregate `ENTITY_MAPPING_WRONG_LOGICALNAME`. Do not equate nominal component counts or matching object IDs with exact approved composition.
- Independent metadata resolution found the four `Information` Main forms and the four public active views by their approved names. `ValidateApp` reported zero blocking errors and nine warnings: eight unresolved required-component warnings associated with those forms/views, plus the non-blocking functional warning with code `-2147155691`.
- GET-only `RetrieveAppComponents` returned HTTP 404; this is not evidence of an empty app. The fresh Site Map XML had only its placeholder navigation, and a local deterministic semantic projection proposed the approved Settings > Administration nodes. The projection was not applied because entity identity failed. No Site Map PATCH or publication is eligible.
- **Outcome: FAILED_VALIDATION / NOT READY FOR SITE MAP PATCH.** Request counts: **32 GET**, **0 AddAppComponents POST**, **0 RemoveAppComponents POST**, **0 Site Map PATCH**, **0 other POST**, **0 PublishXml**, **0 app publish**, **0 role changes**, **0 retries**. `WritesMayHaveOccurred=false`; the app remains unpublished.
- Regression validation passed **118** app-composition assertions, **550** provisioning/recovery assertions, **11** readiness assertions, and `git diff --check`. Do not repeat AddAppComponents, patch the Site Map, or publish `srapp`. Review the returned `entities` collection contract and supported metadata surface before proposing another guarded read.

## Phase 2D.3H — Wrong System Entity Roots Removed

The owner authorized exactly one RemoveAppComponents operation targeting only the system `entity` component. The request was built from the freshly verified system entity ID, normalized as one `Microsoft.Dynamics.CRM.entity` object with `entityid`, and SHA-256 fingerprinted as `73b431f524303ff55c73fbeab864f6c71fc46debba5aa46bba5d4ed70ff54aae`. It contained no AppModule component row IDs, project table IDs, forms, views, Site Map, roles, or unrelated component types.

- Fresh preflight verified the target and identity guards, unmanaged `os_sr_bso_rs_support` Solution, `os_bso_rs_support` Publisher / prefix `os`, existing `srapp` Active/Unpublished state, one directly associated placeholder Site Map, exact 13-component starting inventory, four shared wrong system-entity object IDs, correct separate project-table IDs, protected forms/views, and unchanged System Administrator/System Customizer roles.
- The single RemoveAppComponents POST returned **HTTP 204**. A Microsoft service request ID was returned by the response headers; no correlation ID or Dataverse error code was returned. No retry occurred.
- The initial post-write snapshot and three follow-up GET-only diagnostic attempts stopped on local handling of the intentional zero-entity interim state. The code was corrected to allow empty entity-resolution inventories. A subsequent guarded read-only run verified **one Site Map, zero entities, four forms, four views, zero other components, nine total**. No project-table roots were added.
- The same Site Map identity and placeholder XML remained directly associated; all four approved Information Main forms and public active views remained present/active; roles were unchanged; `srapp` remained Active/Unpublished. `ValidateApp` succeeded with zero blockers and nine warnings: eight unresolved required-table warnings and `App does not reference at least one entity`. Those warnings are expected until a separately authorized project table-root addition.
- **Outcome: `WRONG_ROOTS_FULLY_REMOVED`.** One logical removal removed all four duplicate system-entity rows. This observed outcome does not establish the cause of the original wrong roots. Do not add the four project table roots, patch the Site Map, or publish under this task.
- Cumulative counts, including the GET-only reconciliation attempts: **166 GET**, **1 RemoveAppComponents POST** (HTTP 204), **0 AddAppComponents POST**, **0 Site Map PATCH**, **0 other POST**, **0 DELETE**, **0 PublishXml**, **0 app publish**, **0 role changes**, and **0 retries**. Final regression validation passed **158** app-composition assertions, **550** provisioning/recovery assertions, **11** readiness assertions, PowerShell parser validation, and `git diff --check`.
- Next task: separately authorize a fresh guarded preflight and at most one AddAppComponents call containing only the four approved entity roots. Stop before Site Map modification or publication.

## Phase 2D.3G — Wrong Roots Confirmed; Repair Not Eligible

This GET-only diagnostic uses the corrected identity chain: `appmodulecomponent.objectid` → a collection query of `entities` by `entityid` → `logicalname`. The appmodulecomponent record ID is a separate identity and must not be compared with entity metadata IDs.

- Two fresh guarded runs passed the VN LMV IT environment checks, PAC/Az/WhoAmI identity agreement, and process-scoped expected-user guard. The unmanaged Solution `os_sr_bso_rs_support`, Publisher `os_bso_rs_support` / prefix `os`, and existing `srapp` (Active/Unpublished) matched. No interactive login or environment switch occurred.
- Each run found the expected direct inventory counts: one existing Site Map, four type-1 entity components, four Information Main forms, and four public active views. All forms/views resolve to the four approved tables and are directly present. The Site Map association and ETag remain present; roles remain System Administrator and System Customizer.
- The four component record IDs are distinct, while their object IDs are equal. Each object ID resolves to exactly one `entities` row with logical name `entity`, and none matches the four project-table IDs. Independently, each project table has one identity row in each of `EntityDefinitions` and `entities`, agreeing on logical name and populated object type code; its MetadataId equals its entities.entityid. The approved payload ID matches both project-table identity surfaces, but no current app entity object ID. This verifies the payload's ID source but does not establish the cause of the wrong live roots.
- The reconstructed original 12-component payload fingerprint is `ac66583cc589e1da351cf95025e3a902d8aa54484e9e68f1ba10ee6569269a50`. Its source logic is known and the IDs agree across the two metadata surfaces. Root cause remains **NOT ESTABLISHED**.
- A RemoveAppComponents candidate contains one unique typed entity reference because the four observed rows share one object ID. Although the action signature is verified, Microsoft documentation available to this run does not specify whether one reference removes all four duplicate appmodulecomponent rows. The candidate's full-envelope SHA-256 is `73b431f524303ff55c73fbeab864f6c71fc46debba5aa46bba5d4ed70ff54aae`; its component-set SHA-256 is `9c15f3af61c7321ae59a1970a2e575a1298532f52c275dd52ecfcc3cc8d492a5`. Do not execute it.
- A separate candidate AddAppComponents payload contains exactly four approved entity references, no forms/views/Site Map/roles/other component types, with full-envelope SHA-256 `dde2748b099e602d43b657b7d26cbda4d682c8569ef4a3afa37bf6616e0fe95c` and component-set SHA-256 `4dcf73fbe3a652f9a63d6f1b9b9a586c20b3be85330122d151b477fed03b148a`. This is not authorization to execute it.
- `ValidateApp` succeeded with zero blocking errors and nine warnings: eight unresolved-required-component warnings associated with the four form/view pairs, plus warning `-2147155691` (“Entity doesn’t reference a form or view. App users will see all forms and views.”). `RetrieveAppComponents` returned HTTP 404 and is unavailable for the current unpublished app; it is not evidence of an empty app.
- The current placeholder Site Map has a fresh ETag. Its local unsubmitted semantic projection proposes Settings > Administration with TA Directory (`os_sr_ta`), Positions (`os_sr_pos`), Candidate Sources (`os_sr_csrc`), and Locations (`os_sr_loc`). No Site Map update was made.
- **Outcome: `WRONG_ROOTS_CONFIRMED_REPAIR_AMBIGUOUS`.** Each run made 41 GET requests, including one ValidateApp and the RetrieveAppComponents 404. Cumulative counts across these two runs are **82 GET**, **0 AddAppComponents POST**, **0 RemoveAppComponents POST**, **0 Site Map PATCH**, **0 other POST**, **0 PublishXml**, **0 app publish**, **0 role changes**, and **0 retries**. No write may have occurred. Regression validation passed **140** app-composition assertions, **550** provisioning/recovery assertions, **11** readiness assertions, and `git diff --check`.
- Next step: investigate the unexplained root mismatch and duplicate-reference removal semantics using supported, non-mutating evidence. Do not execute either candidate action, patch the Site Map, or publish until the ambiguity is resolved and a separate explicit authorization is obtained.

## Phase 2D.3C — GET-Only Composition Diagnosis

The following diagnosis used fresh target and identity guards in a short-lived process. It made no Dataverse writes.

- The prior sanitized execution wrapper did not retain the inner failed predicate. A fresh guarded reproduction now fails first at `Assert-ReferenceUiComponentState -RequireComposed` with `Unexpected direct AppModule component exists.` Eight form/view records match their approved IDs, but the four type-1 object IDs do not match the expected table metadata IDs. All observed `rootappmodulecomponentid` fields are empty and `rootcomponentbehavior` is null.
- Fresh `ValidateApp` succeeds with zero blockers and nine warnings: eight null-message/code-0 asset warnings each require the corresponding type-1 table component; the remaining warning is CRM code `-2147155691`, “Entity doesn’t reference a form or view. App users will see all forms and views.” The local `EntityReferenceWarningCount` predicate checks only the different exact message `App does not reference at least one entity`, so it returns zero and does not detect this warning.
- The fresh Site Map transform passes semantic-preservation and duplicate-ID checks and proposes only the four approved Settings > Administration destinations. A current ETag is available and a PATCH is required, but exact app composition fails; no PATCH is eligible. The existing placeholder XML, AppModule identity/state, Solution/Publisher, role associations, and direct Site Map association remain as read.
- The most recent successful guarded diagnostic reported **30 GET**, **0 POST**, **0 PATCH**, and **0 writes**. Cumulative Phase 2D.3C GET count is **UNKNOWN** because earlier diagnostic attempts terminated during local report formatting before emitting counters. Every request in this phase was GET-only; there was no AddAppComponents POST, Site Map PATCH, other POST, PublishXml, app publish, role change, or retry.
- **Outcome: LIVE_STATE_INCONSISTENCY.** The reproduced current first-failing predicate is exact direct-component reconciliation. The original Phase 2D.3B inner exception was not retained, so do not claim that the reproduction proves its historical error text. Do not repeat AddAppComponents or attempt the Site Map PATCH until component identities and hierarchy are resolved and a separately bounded action is authorized.

## Phase 2D.1 — Historical Live Preflight and Outcome (superseded)

The owner authorized a fresh guarded preflight and conditional composition of only the existing `srapp` with the four approved reference-table experiences. Environment, PAC/Az/WhoAmI identity agreement, process-scoped expected-user guard, unmanaged Solution, Publisher, and prefix matched. No environment switch or interactive login occurred.

- `srapp` remains Active and Unpublished. Its `RetrieveUnpublished` representation reported `componentstate=1`; the published-row GET returned 404. The existing Site Map remains Published and contains a placeholder Area/Group/SubArea only. No distinct unpublished Site Map layer was observed. The Solution export contains one `AppModuleSiteMap.SiteMapUniqueName=srapp` binding; direct `appmodulecomponents` inventory is empty.
- All four reference tables are present in the target Solution: `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc`. The selected Main form for each is Information. The selected public active views are Active TA Directories, Active Positions, Active Candidate Sources, and Active Locations. All twelve table/form/view components are absent from `srapp`; no form/view IDs were fabricated. Read-only dependency results resolve the existing managed app-role associations to System Administrator and System Customizer.
- `ValidateApp` returned warnings `No component is referenced` and `App does not reference at least one entity`, plus the blocking error **`App does not contain Site Map`**. The package-level Site Map binding did not satisfy this validation. The bounded app-component list excluded the existing type-62 Site Map; adding it or using another association path is an unresolved scope decision and was not authorized by the component list.
- **Final outcome: BLOCKED_BEFORE_WRITE.** No Site Map PATCH, AddAppComponents action, POST, PublishXml, publish operation, role change, or retry occurred. The cumulative Phase 2D.1 live-read count is **83 GET requests**; all writes and retries are zero. The final guarded composition DryRun accounted for 25 GETs, with a separate identity WhoAmI GET. The 83 count includes the earlier read-only diagnostics and preflights.
- At the time, the next step was to obtain authorization for the Site Map association. That decision was subsequently provided and executed in Phase 2D.2 above.

## Original Phase 2D Plan (historical; superseded by Phase 2D.1)

### Read-Only Preflight

1. Verify `pac org who` still matches VN LMV IT and the specified URL; never switch environments.
2. Read the AppModule and require the exact ID, display name, and unique name above. Use the documented `RetrieveUnpublished` function for the draft; distinguish `statecode` from `componentstate`. Do not infer the AppModule Publisher from the Solution Publisher.
3. Read `solutioncomponent` and verify AppModule type 80, Site Map type 62, TA Entity type 1, and the existing type-10091 child. Preserve type 10091 and its dependencies; do not remove or reinterpret it.
4. Verify existing Site Map ID `6a02d640-2ccd-f111-a05a-000d3a64b349`, unique name `srapp`, app-aware flag, current XML, and componentstate. The read-only target Solution export contains exactly one `<AppModuleSiteMap>` entry with `SiteMapUniqueName=srapp`, matching the adopted AppModule and live Site Map. This is the exact Solution-package-level binding. The standard `appmodulecomponent` query returned zero rows, so no separate type-62 AppModuleComponent association was observed. Preserve the special export binding and do not add a duplicate Site Map component.
5. Verify TA table `os_sr_ta`, MetadataId `f248212e-b5cb-f111-a05a-7c1e52376817`, ObjectTypeCode `11005`, and its project Solution root with Include Subcomponents.
6. Verify Main Information form `e076f089-e35b-46f3-b123-9cf0463759e5` (type 2/Main, ObjectTypeCode 11005, Active, Published) and public Active TA Directories view `2cb98672-8176-4337-af5e-d6aabcac8f2d` (query type 0, not private, ObjectTypeCode 11005, Active, Published). Both occur in the target unmanaged Solution export under the TA table root; do not treat that as app selection.
7. Re-read app-role links. Do not add/remove roles or change the two observed associations.
8. Stop before any write unless a separate Phase 2D Apply authorization is recorded. Current authorization covers adoption and local planning only.

### Supported Composition Route

Microsoft documents `AddAppComponents` (`POST /api/data/v9.2/AddAppComponents`) with non-null `AppId: Edm.Guid` and non-null `Components: Collection(mscrm.crmbaseentity)`; its guide demonstrates typed `savedquery` and `systemform` records and lists table, sitemap, view, and form components. The equivalent .NET request is `AddAppComponentsRequest` with `AppId` and `Components`. A target-organization `$metadata` GET verified the component entity types and primary keys: `Microsoft.Dynamics.CRM.entity/entityid`, `systemform/formid`, `savedquery/savedqueryid`, and `sitemap/sitemapid`. The candidate table/form/view JSON below is therefore schema-validated, but no AddAppComponents request has been sent, so runtime acceptance remains unverified. `ValidateApp(AppModuleId=...)` is a read-only dependency validation function. `RetrieveAppComponents(AppModuleId=...)` did not retrieve this unpublished draft; direct `appmodulecomponents` queries plus `RetrieveUnpublished` are required for draft read-back.

For navigation, update the existing `sitemapxml` on Site Map `6a02d640-2ccd-f111-a05a-000d3a64b349`. The read-only DryRun inspected the live XML: one Area, one Group, and one SubArea with IDs `area_918af8a3`, `group_8b0502d1`, and `subarea_9787e9c1`; titles are placeholder values. The proposed XML transformation changes only those LCID 1033 title strings and adds `Entity="os_sr_ta"` to the existing SubArea, preserving all node IDs and other attributes. Do not create a new Site Map. The Solution export's existing `AppModuleSiteMap.SiteMapUniqueName=srapp` binding is preserved; therefore no Site Map object is included in the AddAppComponents payload. `pac model genpage add` is for generated pages and is not a standard entity-navigation mechanism.

The AddAppComponents candidate payload is:

```json
{
  "AppId": "3709bb7c-28cd-f111-a05c-70a8a581cbfa",
  "Components": [
    {
      "entityid": "f248212e-b5cb-f111-a05a-7c1e52376817",
      "@odata.type": "Microsoft.Dynamics.CRM.entity"
    },
    {
      "formid": "e076f089-e35b-46f3-b123-9cf0463759e5",
      "@odata.type": "Microsoft.Dynamics.CRM.systemform"
    },
    {
      "savedqueryid": "2cb98672-8176-4337-af5e-d6aabcac8f2d",
      "@odata.type": "Microsoft.Dynamics.CRM.savedquery"
    }
  ]
}
```

The Entity, Site Map, Form, and View keys/types were verified against target `$metadata`; the API guide provides concrete form/view payload examples and documents those supported component classes. The existing Site Map is deliberately omitted because the Solution package already has the unique-name binding. No documented AddAppComponents dry-run/preview accepts proposed components without applying them. `ValidateApp` takes only AppModuleId and validates the App's existing graph; it cannot pre-validate this unsubmitted Components collection. Therefore metadata validates the candidate request shape, not server acceptance. Runtime acceptance on this unpublished App remains UNKNOWN until a separately authorized AddAppComponents execution. Do not use undocumented `appmodulecomponent` CRUD as a substitute.

No dependency evidence shows type 10091 or its type-10094 dependency is required by the TA table, Main form, or public view. Preserve these components and their existing dependency graph; their exact identity does not block this TA composition plan absent a concrete dependency result.

### Exact Write Plan

The following operations are proposals for a separately authorized Phase 2D Apply. None has been executed.

**Write 1: Update the existing Site Map navigation XML.**

- API: Web API `PATCH /api/data/v9.2/sitemaps(6a02d640-2ccd-f111-a05a-000d3a64b349)`; the `sitemap` table reference documents Update and writable `sitemapxml`. Use `If-Match` with the preflight ETag and send only the intended XML field.
- Target/payload: retain Site Map identity `srapp`; transform the live XML to Recruitment Support > Administration > TA Directory, with subarea entity `os_sr_ta`. The offline-tested transformation preserves existing node IDs and all unrelated attributes/localized titles. Do not create a second Site Map or add nonexistent tables/pages.
- Proposed `sitemapxml` value from the current live source (not sent):

```xml
<SiteMap IntroducedVersion="7.0.0.0"><Area Id="area_918af8a3" ResourceId="SitemapDesigner.NewTitle" DescriptionResourceId="SitemapDesigner.NewTitle" ShowGroups="true" IntroducedVersion="7.0.0.0"><Titles><Title LCID="1033" Title="Recruitment Support" /></Titles><Group Id="group_8b0502d1" ResourceId="SitemapDesigner.NewGroup" DescriptionResourceId="SitemapDesigner.NewGroup" IntroducedVersion="7.0.0.0" IsProfile="false" ToolTipResourseId="SitemapDesigner.Unknown"><Titles><Title LCID="1033" Title="Administration" /></Titles><SubArea Id="subarea_9787e9c1" ResourceId="SitemapDesigner.NewSubArea" Icon="/_imgs/imagestrips/transparent_spacer.gif" Client="All,Outlook,OutlookLaptopClient,OutlookWorkstationClient,Web" AvailableOffline="true" PassParams="false" Sku="All,OnPremise,Live,SPLA" Entity="os_sr_ta"><Titles><Title LCID="1033" Title="TA Directory" /></Titles></SubArea></Group></Area></SiteMap>
```
- Expected/read-back: a draft Sitemap layer containing the intended nodes; immediately read the normal Site Map and `RetrieveUnpublishedMultiple` result, compare XML and componentstate. The current query returns the Published row (`componentstate=0`); behavior after PATCH is not tested. Require an Unpublished Site Map layer (`componentstate=1`) and verify AppModule remains `componentstate=1`; otherwise stop before Write 2.
- Failure/uncertain write: stop; read both published and unpublished Site Map representations and compare ETag/XML before any retry. Do not send a compensating overwrite automatically.
- Publication/separate approval: standard PATCH is not the documented publish action; Microsoft documents `PublishXml` separately. Still verify the write did not publish. This write requires explicit Phase 2D authorization and must not be followed by `PublishXml`.

**Write 2: Add the existing table, Main form, and public view to the AppModule.**

- API: Web API `POST /api/data/v9.2/AddAppComponents` (or .NET `AddAppComponentsRequest`), `AppId=3709bb7c-28cd-f111-a05c-70a8a581cbfa`, and the exact typed table/form/view payload above. Component types are Entity `1`, Form `60`, and View `26`. Do not include a Sitemap component because the existing `AppModuleSiteMap` package binding by unique name is verified.
- Expected/read-back: corresponding `appmodulecomponent` associations; read the app component list directly using AppModule unique component ID `81d8d848-2e00-470c-8899-2f55f560e018`, plus `RetrieveAppComponents` if supported for the draft. Verify table/form/view IDs and types, confirm the existing `AppModuleSiteMap.SiteMapUniqueName=srapp` export binding remains, and verify no other component was added.
- Failure/uncertain write: stop; query all intended component IDs and types before retrying. If only some appear, preserve them and get a new recovery decision; do not automatically remove/re-add.
- Publication/separate approval: Microsoft documents app publication as a later, separate `PublishXml` step. Confirm app remains Unpublished after association. This write requires explicit Phase 2D authorization; do not change app-role associations.

**Atomicity and bounded sequence:** No change set is used. Microsoft documents general OData change-set atomicity, but no evidence here establishes that AddAppComponents is supported inside one. The script executes at most two independent write requests: (1) Site Map PATCH, then immediate GET read-back; (2) AddAppComponents, then independent component/AppModule/Site Map GET read-back and ValidateApp. These requests are **not transactional**. If Write 1 succeeds and Write 2 fails, preserve the partial Sitemap draft and stop; do not retry, delete, or roll back automatically.

### Post-Write Read-Back and Gates

1. Read AppModule identity/state and `componentstate`; require actual unique name `srapp` and Unpublished. Do not compare it to `os_srapp` or rename it.
2. Read direct `appmodulecomponents`, Site Map normal and unpublished layers, and Solution components; verify all exact IDs and navigation references.
3. Run `ValidateApp(AppModuleId=3709bb7c-28cd-f111-a05c-70a8a581cbfa)` and inspect every `ValidationIssueList` item. Validation is not publication.
4. Confirm only TA exists in navigation. Do not add Candidate, Interview, Position, Source, or Location entries; the other tables do not exist.
5. Preserve System Administrator/System Customizer associations; no role assignment or end-user role changes.
6. Do not call `PublishXml`, Publish All Customizations, Site Map Publish, solution import, or any publication operation. The app must remain Unpublished. If an operation publishes automatically, stop and treat the route as unsuitable.
7. On any timeout or ambiguous result, reconcile with GETs before retrying. Do not assume rollback unless the entire operation was inside a verified supported change set.

**Historical Phase 2D pre-authorization readiness was BLOCKED.** The later Phase 2D.1 owner authorization did not override its bounded component list; its fresh validation found the separate missing-Site-Map blocker described above. The AppModule Publisher and type-10091 identity remain unknown. Do not use this historical plan as an Apply authorization or as evidence that Site Map inclusion is approved.

## Historical Phase 2C Target (superseded)

- App display name: **BSO-RS-Support**.
- Owner-approved caller-supplied unique-name suffix: **srapp**.
- Expected final unique name: **os_srapp**; independently verify after creation.
- Solution: **os_sr_bso_rs_support**; Publisher: **os_bso_rs_support**, prefix **os**.
- Initial publication state: **Unpublished**.
- Initial table/navigation: `os_sr_ta` at **Recruitment Support > Administration > TA Directory**.
- Main form: existing **Information** form, type **main**.
- Initial default public view: **Active TA Directories**, query type `0`.
- Other tables, navigation, security-role associations, publication, and generated/Custom Pages are out of initial scope.

## Tool Capabilities

| Surface | Supported here | Limitation / guard |
|---|---|---|
| PAC CLI 2.13.1 | `pac model create`, `list`, `list-tables`; genpage management; Solution export | `model create` cannot set the app unique name. Omitting `--publish` is required for the unpublished shell. It cannot configure the Area/Group/entity SubArea in this initial command. |
| AppModule SDK/Web API | Create `appmodule` with name, unique name, description and default web resource; use `SolutionUniqueName` on supported Create request/header | Caller-supplied `srapp` was approved for expected final name `os_srapp`. Phase 2C-R2 verified an existing AppModule `srapp`, Active but `componentstate=1` (Unpublished); its type-80 Solution component matches the App ID. The historical Create request is superseded and must not be sent. |
| Model-driven app APIs | `AddAppComponents`, `RetrieveAppComponents`, `ValidateApp`, and `PublishXml` | Use typed components/IDs from read-only metadata. Add forms/views only after explicit selection. Validation and publication are separate. |
| AppModuleComponent metadata | Component type values include Entity `1`, View `26`, Form `60`, Sitemap `62` | Use supported app APIs/designer rather than directly creating internal app-module component rows. |
| Forms and views | Dataverse SDK CRUD on `systemform` and `savedquery`; AddAppComponents binds existing components to the app | Do not change approved TA layout/query metadata in this phase. Form XML and FetchXML are not required to add existing components. |
| Sitemap | Supported SiteMap XML component/record and AddAppComponents association; Power Apps app designer is also supported | Use designer-generated, schema-valid SiteMap XML as the source template. Genpage add/upload is for generated pages, not ordinary entity navigation. |
| Dataverse MCP | Current session supports metadata schema descriptions, selected metadata SQL reads, and Solution export via PAC | No dedicated model-driven app composition tool was exposed. The generic Custom API invoker is not a generic caller for every standard action. Metadata SQL did not successfully return TA systemform/savedquery records; export was used to inspect Solution metadata. |
| Official skills | `dv-connect`, `dv-metadata`, `dv-solution`, and `dv-security` are present in `.agents/skills` | `dv-metadata` covers schema/forms/views; `dv-solution` covers ALM; `dv-security` covers access. None provides a complete app shell + sitemap deployment workflow. |

## Historical Phase 2C Read-Only Preflight

Run these before any future write. Stop on any target mismatch; never switch environments.

```powershell
$org = 'https://org14938ec2.crm4.dynamics.com'
pac env who
pac solution list --environment $org
pac model list --environment $org
pac model list-tables --environment $org --type custom --search os_sr_ta,os_sr_pos,os_sr_csrc,os_sr_loc
```

The expected identity is VN LMV IT and the URL above. Phase 2C-R2 verified that the app already exists with actual unique name `srapp`; do not run the historical Create request or substitute `os_srapp`. Any future adoption work requires separate owner approval, confirmation of the naming exception, review of type 10091, least-privilege app roles, and approved app composition. Confirm TA form/view IDs and metadata with read-only metadata queries. Do not read table rows. Do not invoke the failed Position metadata operation.

For Solution membership, use PAC `solution list`, read-only `solutioncomponent` queries, `RetrieveAppComponents` for the app after it exists, and an export read-back. A TA table root component with `rootcomponentbehavior=0` includes its table subcomponents in the Solution; the app’s own component selection is separate.

## Historical Phase 2C Name Proposal and Held Create Request (superseded)

Installed command help:

```text
pac model create [--environment] --name [--description] [--solution] [--publish]
```

There is no `--unique-name` option. This command can associate the app with the Solution but cannot set `os_srapp`.

Microsoft's [AppModule creation guidance](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code) states that caller-supplied `uniquename` uses English letters and numbers and Dataverse automatically prepends the Solution Publisher prefix. With prefix `os`, caller value `srapp` is compliant and the documented expected final name is `os_srapp`. The AppModule reference lists `uniquename` as a writable string of maximum length 100. The [optional-parameter guidance](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/optional-parameters) documents associating a Create request with a Solution by `SolutionUniqueName` (SDK request parameter) or `MSCRM.SolutionUniqueName` (Web API header).

PAC lists five apps. Phase 2C-R2 `RetrieveUnpublished` confirms BSO-RS-Support with actual unique name `srapp`, `statecode=0`/`statuscode=1` (Active), and `componentstate=1` (Unpublished); no published AppModule row was returned. No `os_srapp` unique name exists. The app's ID matches the type-80 Solution-component root in the project and Default Solutions. The mismatch requires owner ratification before adopting `srapp`; it is not authorization to create another app.

The project Solution query returns a type-10091 non-metadata child row whose `rootsolutioncomponentid` points to the type-80 component. The live sitemap ID matches the type-62 Site Map component object ID; type 10091's object ID differs. Dependency rows show type 10091 has a Published dependency on the type-80 AppModule and an Unpublished dependency on a separate type-10094 component. The latter is present in Default and managed `msdyn_AppFrameworkInfraExtensions`. Type 10091's exact identity is **UNKNOWN** and it is not the Site Map record itself; no evidence establishes corruption.

The following is the historical Phase 2C request, **not sent and superseded by Phase 2C-R2**. It is retained only as an audit record and is not actionable. Do not send it: the existing AppModule is the subject of the R2 adoption assessment, and no AppModule creation is authorized.

```http
POST <verified-organization-url>/api/data/v9.2/appmodules
Content-Type: application/json; charset=utf-8
Accept: application/json
OData-Version: 4.0
OData-MaxVersion: 4.0
MSCRM.SolutionUniqueName: os_sr_bso_rs_support

{
  "name": "BSO-RS-Support",
  "uniquename": "srapp",
  "description": "Internal recruitment support application for authorized BSO candidate operations, backed by Dataverse.",
  "webresourceid": "953b9fac-1e5e-e611-80d6-00155ded156f"
}
```

Expected final `uniquename`: `os_srapp`. The request leaves out `PublishXml` and does not set internal `componentstate`; read it back and require the AppModule to remain unpublished (`componentstate=1`, Unpublished) before any further step. Confirm the default web resource is available in the target first. If name, Publisher, Solution, or publication state differs, stop; do not patch, rename, retry, delete, or recreate.

## Historical Phase 2C Composition Sequence (superseded by the R3 plan above)

Every write step below is a future phase requiring its own explicit authorization. The automation should default to plan/read-only mode and require an explicit Apply switch plus typed confirmation for each authorized change batch.

1. **Reconcile the pre-existing BSO-RS-Support app.** Confirm its owner/history and intended disposition with the project owner/admin. Do not rename, delete, recreate, or alter its Solution components in this phase. Component type 10091 remains identity-unknown; do not remove it.
2. **Do not create while the same-display-name app exists.** A future action requires a new explicit owner direction after reconciliation, even though the current one-AppModule authorization has not been exercised. Preserve the requested `os_srapp` name; do not substitute automatically.
3. **Verify app identity and Solution.** Independently read the AppModule row and Solution component membership. Confirm exact display/unique names, Publisher, Solution, app state, and unpublished component state. Do not proceed on mismatch.
4. **Add TA table component.** Resolve the TA metadata ID with a GET and use `AddAppComponents` or app designer for the `os_sr_ta` table. Read back `RetrieveAppComponents`; access no table rows.
5. **Configure sitemap.** Add Recruitment Support > Administration > TA Directory using supported SiteMap/app APIs or app designer and read back. Generated-page commands do not create ordinary table SubAreas.
6. **Select UI components.** Add only the existing Main `Information` form and `Active TA Directories` public view after resolving current IDs and state. Do not change the form/view metadata.
7. **Validate.** Call `ValidateApp`, inspect the complete `ValidationIssueList`, and verify Solution/app component membership. Do not change role assignments.
8. **Remain unpublished.** Publication requires separate approval. Only then may scoped `PublishXml` be considered. Export for ALM read-back; do not alter Git.

## API Operation References

Use supported Microsoft actions and SDK request types; do not handcraft opaque internal app graph data:

- Historical, superseded Phase 2C Create only: `POST /api/data/v9.2/appmodules`, with the `MSCRM.SolutionUniqueName` optional parameter. Do not use this operation for the adopted app.
- Add selected app components: `POST /api/data/v9.2/AddAppComponents` with `AppId` and typed `Components`; Microsoft examples include `savedquery` and `systemform`. The action documentation also lists sitemap, entity, dashboard, and business-process-flow components.
- Read app selection: `GET /api/data/v9.2/RetrieveAppComponents(AppModuleId=<GUID>)`.
- Validate: `GET /api/data/v9.2/ValidateApp(AppModuleId=<GUID>)`.
- Publish only after separate approval: `POST /api/data/v9.2/PublishXml` with only the target app ID in `<appmodules>`.

For standard forms/views, the `dv-metadata` skill documents `systemform` and `savedquery` SDK record CRUD. The app designer/API selection of those existing records is distinct from creating or editing them.

## Failure and Recovery

The following Phase 2C-R2 outcome is retained as history. Its “adoption not authorized” conclusion was superseded by the owner's Phase 2C-R3 approval; the Phase 2D execution gate remains closed.

- Stop after the first failed or ambiguous write. Do not automatically retry.
- Read back AppModule, Solution membership, app component list, sitemap, and selected forms/views before proposing any follow-up.
- If an object exists but is incomplete, preserve it and report the partial state. No automatic delete, rename, recreate, or publish.
- No table creation, business-row access, security-role changes, audit changes, environment switch, or Git operation is part of this app phase.
- Keep the Phase 1D-D Position 401 separate. Its cause remains **UNKNOWN**; successful GETs or app creation do not resolve it. Do not retry Position.
- Phase 2C-R2 read-only outcome: AppModule ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`, unique name `srapp`, display name BSO-RS-Support. `RetrieveUnpublished` reports Active state and `componentstate=1`; the published row is absent. The app has no appmodulecomponent rows, empty appgraph/configxml, a Published but blank placeholder sitemap, and two app-role associations (System Administrator and System Customizer). Type 10091 is not the sitemap object ID; it depends on the AppModule and a separate type-10094 component, while its exact identity remains unknown. Classification is B, conditional on owner-approved naming, navigation/component/security changes and type-10091 review. Adoption is not authorized. No Dataverse writes or business-row reads occurred.

## References

- [App Manifest](MODEL_DRIVEN_APP_MANIFEST.md)
- [VS Code Power Platform Autobuild](VS_CODE_POWER_PLATFORM_AUTOBUILD.md)
- [Current State](CURRENT_STATE.md)
- [PAC model command reference](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/model)
- [Create, manage, and publish model-driven apps using code](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code)
- [Create or edit a model-driven app](https://learn.microsoft.com/en-us/power-apps/maker/model-driven-apps/create-edit-app)
- [Add or edit app components](https://learn.microsoft.com/en-us/power-apps/maker/model-driven-apps/add-edit-app-components)
- [Create a model-driven app Site Map](https://learn.microsoft.com/en-us/power-apps/maker/model-driven-apps/create-site-map-app)
- [Site Map table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/sitemap)
- [AddAppComponents](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/addappcomponents)
- [AddAppComponentsRequest (.NET SDK)](https://learn.microsoft.com/en-us/dotnet/api/microsoft.crm.sdk.messages.addappcomponentsrequest)
- [RetrieveAppComponents](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrieveappcomponents)
- [RetrieveUnpublished](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrieveunpublished)
- [ValidateApp](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/validateapp)
- [PublishXml](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/publishxml)
- [Execute batch operations and transactional change sets](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/execute-batch-operations-using-web-api)
- [AppModuleComponent](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/appmodulecomponent)
- [Use optional parameters](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/optional-parameters)
