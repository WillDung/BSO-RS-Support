# Model-driven App and Sitemap Automation Runbook
**Current status — 23 October 2026:** Phase 2D.3C is **LIVE_STATE_INCONSISTENCY**. The live `srapp` inventory has 13 direct records by type count, but its four type-1 object IDs do not match the four approved reference-table metadata IDs, and the form/view root links are empty. The exact-component reconciliation predicate fails. The existing Site Map remains Published with placeholder navigation; `srapp` remains Active/Unpublished. No additional write, retry, or publication occurred during diagnosis.

**Historical adoption status — 21 October 2026:** The owner adopted the existing BSO-RS-Support AppModule `srapp` (ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`) in `os_sr_bso_rs_support`. The actual unique name is `srapp`; `os_srapp` is superseded and must not be used or applied by renaming.

The dated adoption-status paragraph below records the pre-Phase 2D.1 state and is superseded by this current status and the Phase 2D.2 result.

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
