# BSO-RS-Support Model-driven App Manifest

**Status:** Phase 2C-R3 official adoption recorded, 21 October 2026. The owner adopted the existing BSO-RS-Support AppModule with actual unique name `srapp`; Phase 2C is closed by adoption, not by a successful Create. Phase 2D.2 verified the existing Site Map association. Phase 2D.3 is authorized, but its latest live preflight stopped before any Dataverse request because the required process-scoped target and expected-user guards were unavailable. The AppModule Publisher lookup and component type 10091 identity remain unknown.

**Phase 2D.1 historical status — 22 October 2026 (superseded by Phase 2D.2 below):** The owner-authorized Phase 2D.1 preflight returned `App does not contain Site Map` and stopped before any write. The later Phase 2D.2 authorization resolved that blocker by associating the existing Site Map.

## Phase 2D.3 Current Status — Blocked Before Write

The Phase 2D.2 Site Map association remains the last verified live state. Phase 2D.3 local guarded orchestration and synthetic coverage are implemented, but the fresh live preflight stopped at `Verify PAC target`: the process-scoped environment and expected-user guards were unavailable. No Dataverse Web API request or write occurred in the Phase 2D.3 attempt. The app is therefore still documented as Site-Map-only, Active/Unpublished; reference components and navigation are not verified as composed.

## Current Adopted App Manifest

```yaml
apiVersion: bso-rs-support/v1
kind: adoptedModelDrivenApp
status: phase-2d3-authorized-preflight-blocked-before-write
asOf: 2026-10-22
adoption:
  ownerApproved: true
  phase2cDisposition: closed-by-adoption-no-create
  phase2dAuthorized: true
  phase2dAuthorizationScope: bounded-four-reference-table-composition
  phase2dExecutionStatus: verified-sitemap-associated
  phase2d2AuthorizationScope: existing-sitemap-component-only
  phase2d3AuthorizationScope: four-reference-table-composition-and-existing-sitemap-patch-no-publish
  phase2d3ExecutionStatus: blocked-before-write-missing-process-guards
  renameAllowed: false
  recreateAllowed: false
app:
  displayName: BSO-RS-Support
  uniqueName: srapp
  appModuleId: 3709bb7c-28cd-f111-a05c-70a8a581cbfa
  namingException: actual-srapp-supersedes-os_srapp-proposal
  appState: Active
  componentState: Unpublished
  publishedOn: not-returned
  publisherUniqueName: unknown-not-independently-verified
  solutionUniqueName: os_sr_bso_rs_support
  solutionMembership: verified-type-80-root
  solutionPublisherUniqueName: os_bso_rs_support
  solutionPublisherStatus: verified
  appPublisherStatus: unknown
currentSiteMap:
  name: BSO-RS-Support
  uniqueName: srapp
  siteMapId: 6a02d640-2ccd-f111-a05a-000d3a64b349
  solutionComponentType: 62
  publicationState: Published
  solutionPackageBinding: AppModuleSiteMap.SiteMapUniqueName=srapp
  standardAppModuleComponentRow: verified-present
  appComponentAssociation: verified-present-after-phase-2d2
  content: placeholder-area-group-subarea-only
  subareaTarget: none
  unpublishedLayerQuery: returned-componentstate-0-no-distinct-draft-observed
proposedComposition:
  status: site-map-associated-reference-components-pending-live-preflight
  navigation:
    area: Settings
    group: Administration
    subareas:
      - TA Directory
      - Positions
      - Candidate Sources
      - Locations
  appComponents:
    plannedTableFormViewCount: 12
    currentState: site-map-only
    directComponentInventory:
      siteMap: verified-present
      tableFormViewComponents: absent
    entries:
      - table: os_sr_ta
        mainForm: Information
        publicActiveView: Active TA Directories
      - table: os_sr_pos
        mainForm: Information
        publicActiveView: Active Positions
      - table: os_sr_csrc
        mainForm: Information
        publicActiveView: Active Candidate Sources
      - table: os_sr_loc
        mainForm: Information
        publicActiveView: Active Locations
  validation:
    status: site-map-error-cleared
    remainingWarning: App does not reference at least one entity
    warnings:
      - App does not reference at least one entity
    directAppModuleComponents: existing-sitemap-only
    solutionPackageSiteMapBinding: present
  components:
    table:
      logicalName: os_sr_ta
      metadataId: f248212e-b5cb-f111-a05a-7c1e52376817
      objectTypeCode: 11005
      solutionMembership: verified-table-root-includes-subcomponents
      appSelection: not-yet-added
    mainForm:
      name: Information
      formId: e076f089-e35b-46f3-b123-9cf0463759e5
      formType: 2
      entityObjectTypeCode: 11005
      activationState: Active
      componentState: Published
      solutionInclusion: verified-in-target-solution-export
      appSelection: not-yet-added
    publicView:
      name: Active TA Directories
      savedQueryId: 2cb98672-8176-4337-af5e-d6aabcac8f2d
      queryType: 0
      isPrivate: false
      state: Active
      componentState: Published
      solutionInclusion: verified-in-target-solution-export
      appSelection: not-yet-added
security:
  currentAppRoles:
    - System Administrator
    - System Customizer
  projectEndUserRole: unknown-not-verified
  changesAuthorized: false
publication:
  currentAppState: Unpublished
  publishAllowed: false
  publishRequiresSeparateApproval: true
unresolved:
  - appmodule-publisher-lookup
  - solution-component-type-10091-exact-identity
  - Phase-2D3-live-preflight-requires-approved-process-scoped-target-and-expected-user-guards
  - sitemap-PATCH-unpublished-layer-behavior-not-tested
```

The Solution Publisher `os_bso_rs_support` is verified; the AppModule's Publisher lookup was not returned and is not inferred from Solution membership. R2 remains the detailed adoption baseline; the R3-P GET-only DryRun subsequently reconfirmed the AppModule state, Site Map XML/state, solution membership, form/view metadata, and package-level unique-name binding. Form/view IDs above are verified metadata/Solution-export records, not app associations. `componentstate=Unpublished` is distinct from `statecode=Active` and from the Published Site Map state.

## Phase 2D.1 Historical Live Preflight (superseded by Phase 2D.2)

On 22 October 2026, the owner-authorized guarded GET-only preflight matched the target environment, PAC/Az/WhoAmI identities, expected-user guard, unmanaged Solution, and Publisher. The adopted AppModule is still Active/Unpublished. The existing Site Map is Published and placeholder-only; its Solution package binding is present, but no direct AppModuleComponent association exists. The four tables are in the Solution. Their selected Main forms are Information and their public active views are Active TA Directories, Active Positions, Active Candidate Sources, and Active Locations. All twelve table/form/view components are absent from the app.

Live `ValidateApp` returned two warnings (`No component is referenced`; `App does not reference at least one entity`) and the blocking error **`App does not contain Site Map`**. The package-level binding was insufficient. The approved component list did not include the existing Site Map, so the operation stopped before write pending an explicit scope decision. **Outcome: BLOCKED_BEFORE_WRITE.** Counts: 83 GET; zero Site Map PATCH, AddAppComponents operation, POST, PublishXml, publish operation, role change, and retry. See the [Phase 2D.1 runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md) for the detailed verification and next gate.

## Phase 2D-P Read-Only Verification

The GET-only DryRun on 21 October 2026 reconfirmed AppModule `srapp` as Active (`statecode=0`) and Unpublished (`componentstate=1`), with no AppModule Publisher lookup. The Site Map `srapp` is app-aware and Published (`componentstate=0`); its live XML contains only the placeholder Area/Group/SubArea and the same IDs recorded above. `RetrieveUnpublishedMultiple` returned the Site Map with `componentstate=0`; no distinct Unpublished Site Map layer was observed. The unmanaged Solution export has exactly one `AppModuleSiteMap` entry with `SiteMapUniqueName=srapp`, matching the AppModule and live Site Map unique names. Direct `appmodulecomponents` remains empty. This is the exact package-level Sitemap binding; it is not a direct standard AppModuleComponent row.

The target OData `$metadata` GET verified `AddAppComponents(AppId: Edm.Guid, Components: Collection(mscrm.crmbaseentity))` and primary keys/types `entity/entityid`, `systemform/formid`, `savedquery/savedqueryid`, and `sitemap/sitemapid`. The proposed request uses the table, Main form, and public view only; it omits the Site Map because the existing `AppModuleSiteMap` binding is present. Microsoft documents the action and typed form/view examples, but no action request was sent, so runtime acceptance remains untested. The runbook's Site Map change preserves all three node IDs and unrelated XML attributes while changing titles and adding the TA entity target.

The same DryRun reverified the TA Main form and Active TA public view identities/states, target Solution roots (type 80 AppModule, 62 Site Map, 1 TA table, plus type 10091 child), and the two app-role associations (System Administrator/System Customizer). No app composition, publication, role/audit change, business-row read, or Dataverse write occurred. See the [local script](../scripts/Configure-BsoRsModelDrivenApp.ps1), [offline tests](../tests/ModelDrivenAppComposition.Tests.ps1), and [Phase 2D runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md).

The former `os_srapp` YAML proposal and all following Phase 2C-R2 environment, naming, and component-plan sections are retained as historical decision evidence only. Their app-name target and “not adopted” status are superseded by the R3 owner decision; do not treat those sections as the current manifest.

## Historical Phase 2C-R2 Manifest (superseded)

```yaml
apiVersion: bso-rs-support/v1
kind: modelDrivenApp
status: proposed
app:
  displayName: BSO-RS-Support
  uniqueName: os_srapp
  callerSuppliedUniqueName: srapp
  uniqueNameStatus: owner-approved-not-created
  namingConventionException: true
  description: >-
    Internal recruitment support application for authorized BSO candidate
    operations, backed by Dataverse.
  appType: model-driven
  initialPublicationState: unpublished
  solutionUniqueName: os_sr_bso_rs_support
  publisherUniqueName: os_bso_rs_support
  publisherPrefix: os
navigation:
  status: proposed
  area:
    title: Recruitment Support
    groups:
      - title: Administration
        subareas:
          - title: TA Directory
            pageType: entityList
            tableLogicalName: os_sr_ta
components:
  implemented:
    - kind: table
      logicalName: os_sr_ta
      displayName: TA Directory
      solutionMembership: verified-root-component
  planned:
    - kind: appmodule
      displayName: BSO-RS-Support
      uniqueName: os_srapp
      callerSuppliedUniqueName: srapp
      publicationState: unpublished
    - kind: table
      logicalName: os_sr_ta
      appSelection: proposed
    - kind: form
      tableLogicalName: os_sr_ta
      displayName: Information
      formType: main
      appSelection: proposed
    - kind: publicView
      tableLogicalName: os_sr_ta
      displayName: Active TA Directories
      queryType: 0
      default: true
      appSelection: proposed
  excludedInitially:
    - displayName: Information
      formType: card
    - displayName: Information
      formType: quick
    - displayName: Inactive TA Directories
    - displayName: Quick Find Active TA Directories
    - displayName: TA Directories
      queryType: 8192
    - displayName: TA Directory Advanced Find View
    - displayName: TA Directory Associated View
    - displayName: TA Directory Lookup View
securityDependencies:
  status: unresolved
  requirements:
    - App users require an approved role assignment that includes app access.
    - Table, row, and column privileges remain governed by the separate Security Model.
    - TA remains a directory contact, not an app role.
  changesAuthorized: false
publication:
  initialState: unpublished
  publishAllowed: false
  requiresSeparateApproval: true
futureNavigation:
  status: proposed-only
  tables:
    - os_sr_pos
    - os_sr_csrc
    - os_sr_loc
    - os_sr_cand
```

The manifest separates deployed metadata from planned app composition. `appSelection: proposed` does not mean the form or view is currently in an app. Form/view display labels are not unique identifiers; implementation must resolve component IDs and type from read-only Dataverse metadata immediately before composition.

## Verified Environment Snapshot

Read-only checks on 21 October 2026 confirmed:

- PAC identity matches VN LMV IT at the approved organization URL and environment/organization IDs.
- Publisher `os_bso_rs_support` has prefix `os`; Solution `os_sr_bso_rs_support` is unmanaged version `1.0.0.0` and linked to that Publisher.
- PAC lists five model-driven apps. BSO-RS-Support has App ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`, actual unique name `srapp`, and Active state. `RetrieveUnpublished` returns `componentstate=1` (Unpublished); no published AppModule row was returned, and `publishedon` was absent. The unpublished representation did not return the AppModule Publisher lookup; the project Solution Publisher is verified separately. The App ID matches the type-80 root in both the project and Default Solutions. The AppModule row records Created On and Modified On as `2026-10-21T08:22:10Z`; Created By and Modified By resolve to the active PAC user. Delegate fields were absent.
- The only project custom table is `os_sr_ta`. Position, Candidate Source, and Location remain absent. No business rows were read.
- The project Solution includes the TA Entity root with `rootcomponentbehavior=0` (Include Subcomponents). A temporary read-only Solution export contained TA metadata, three forms, and seven views; the archive was inspected for selected labels/types only and removed.
- TA forms exported: Information (`main`), Information (`card`), and Information (`quick`). TA views include Active TA Directories (public type 0, default), Inactive TA Directories (type 0), Quick Find Active TA Directories (type 4), TA Directories (type 8192), Advanced Find (type 1), Associated (type 2), and Lookup (type 64).
- The target Solution has three root objects: type 80 AppModule, type 62 Site Map, and type 1 TA table; type 10091 is a child of the type-80 root. The type-62 object ID matches the live app-aware `srapp` Site Map ID. The Site Map is Published (`componentstate=0`) but its XML contains only a placeholder Area, Group, and SubArea; no Entity, URL, or page target is present. Its ID differs from type 10091's object ID.
- Both Web API and MCP queries returned zero `appmodulecomponent` rows for the app's unique component ID. The draft `appgraph` and `configxml` are empty. The supported `RetrieveAppComponents` function did not retrieve this unpublished draft. No app-linked form, view, or page association was found; the TA forms/views in the Solution are definitions, not verified app selections.
- The app-role intersection contains two active managed associations: System Administrator and System Customizer. No project-specific end-user role was found. The AppModule's actual name `srapp` differs from the previously expected `os_srapp`; accepting it requires an explicit owner naming-exception decision. No adoption, create, edit, or publish operation occurred in Phase 2C-R2.
- Type 10091 is a non-metadata child of type 80 (`rootsolutioncomponentid` points to the type-80 solutioncomponentid; `rootcomponentbehavior=0`). Live dependency rows show a Published dependency on the type-80 AppModule and an Unpublished dependency on type 10094. The type-10094 object exists in Default and managed `msdyn_AppFrameworkInfraExtensions`; it is distinct from the visible sitemap ID. Type 10091's exact public identity remains **UNKNOWN** and it is **not the Site Map record itself**. No corruption is established, but owner/admin review is required before adoption.
## Historical Phase 2C-R2 Naming Proposal and Verification (superseded)

Installed PAC 2.13.1 `pac model create` exposes display name, description, environment, Solution, and optional publish, but **no technical-name parameter**. It cannot guarantee `os_srapp`; the proposed AppModule API path is required if the technical name is accepted.

Microsoft's [AppModule creation guidance](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code) says the supplied `uniquename` uses English letters and numbers and that Dataverse automatically prepends the Solution Publisher prefix. The AppModule table reference exposes `uniquename` as a writable string (maximum length 100). Thus `srapp` meets the documented input character rule; with prefix `os`, the documented expected final value is `os_srapp`. The Web API/SDK path permits the caller to supply `uniquename`, unlike PAC `model create`.

The live app inventory contains five apps; a direct read-only `appmodule.uniquename` query for `os_srapp` returned no rows, but PAC lists a BSO-RS-Support app with unique name `srapp`. This existing same-display-name app is a confirmed creation conflict even though its unique name differs. The target Solution and Publisher were independently verified. Do not create a second app under the same display name. After owner/admin reconciliation and new direction, any authorized creation must independently read back `appmodule.uniquename`, Publisher, Solution, and publication state. If the final name differs from `os_srapp`, stop; do not rename, delete, recreate, or accept a substitute automatically.

The owner has approved this component-specific exception for the app only. The project-wide `os_sr_*` convention remains unchanged for every other component. This exception does not alter table names, Solution names, or Publisher settings. Actual prefix behavior and final name still require post-create read-back.

The AppModule Create API accepts a unique-name property, and the documented `SolutionUniqueName` parameter can associate a supported Create request with the existing Solution. Any future approved path must independently read back the final `appmodule.uniquename`, Publisher, Solution, and unpublished state before configuring components.

## Historical R2 Component Plan (superseded by the current manifest above)

| Component | Current evidence | Dependency for initial app |
|---|---|---|
| TA Directory table | Exists; exact schema verified in [Current State](CURRENT_STATE.md); root Solution membership verified | Table must be added to the app module and shown in the app sitemap |
| Main form | `Information`, type `main`, included in exported TA solution metadata | Resolve its current `formid`, active/published state, and app eligibility; add only after read-back |
| Card and Quick forms | `Information`, types `card` and `quick` | Excluded from initial app unless separately requested |
| Public views | Active and Inactive TA Directories, query type 0 | Select Active as initial default; resolve current IDs and verify default/active state |
| System views | Quick Find, advanced-find, associated, lookup, and type-8192 TA Directories views | Do not include explicitly in initial app without a documented need; some views serve platform lookup/search behavior and are not normal sitemap pages |
| Sitemap | Existing app-aware BSO-RS-Support/`srapp` sitemap exists in Default Solution; no `os_srapp` app sitemap is verified | Do not edit or reuse it until app identity/ownership is reconciled; future sitemap attachment is separately approved |
| App access | No role assignment was changed in Phase 2C; existing app access association is not verified | Requires a later security review and separate approval; do not assign roles in Phase 2C |

The existing solution export confirms form/view component definitions, but not which will be selected in a new app. App-specific selection and deployment membership must be verified after configuration.

## Future Navigation

The only approved initial table target in this app proposal is `os_sr_ta`. `os_sr_pos`, `os_sr_csrc`, `os_sr_loc`, and candidate workflow tables remain future navigation proposals until the table schema exists, is approved, and is independently verified. The historic Position HTTP 401 is a separate incident: root cause remains **UNKNOWN**; no retry is authorized by this manifest.

## References

- [Current State](CURRENT_STATE.md)
- [Project Context](PROJECT_CONTEXT.md)
- [Architecture](ARCHITECTURE.md)
- [Security Model](SECURITY_MODEL.md)
- [ALM and Deployment](ALM_DEPLOYMENT.md)
- [VS Code Power Platform Autobuild](VS_CODE_POWER_PLATFORM_AUTOBUILD.md)
- [App and Sitemap Automation Runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md)
- [PAC model command reference](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/model)
- [Create, manage, and publish model-driven apps using code](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code)
- [AppModule table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/appmodule)
- [RetrieveUnpublished function](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrieveunpublished)
- [RetrieveAppComponents function](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrieveappcomponents)
