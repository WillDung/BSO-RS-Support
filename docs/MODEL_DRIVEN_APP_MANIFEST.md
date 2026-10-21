# BSO-RS-Support Model-driven App Manifest

**Status:** Phase 2C creation blocked, 21 October 2026. The project owner approved exactly one unpublished AppModule with caller suffix `srapp`, expected final `os_srapp`, as an app-only exception to `os_sr_*`. Read-only discovery found an existing BSO-RS-Support app with unique name `srapp`, so creating a second same-display-name app is blocked. No app resource was created in Phase 2C. The separate Phase 1D-D `os_sr_pos` HTTP 401 incident remains **UNKNOWN** and is not resolved by this app work.

## Manifest

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
- Five model-driven apps appear in PAC inventory. BSO-RS-Support exists with actual unique name `srapp` and status **Saved - Not Published**; no `os_srapp` unique name exists. The existing app's App ID matches the type-80 root component in both the project Solution and Default Solution. This is a pre-existing app, not one created by Phase 2C.
- The only project custom table is `os_sr_ta`. Position, Candidate Source, and Location remain absent. No business rows were read.
- The project Solution includes the TA Entity root with `rootcomponentbehavior=0` (Include Subcomponents). A temporary read-only Solution export contained TA metadata, three forms, and seven views; the archive was inspected for selected labels/types only and removed.
- TA forms exported: Information (`main`), Information (`card`), and Information (`quick`). TA views include Active TA Directories (public type 0, default), Inactive TA Directories (type 0), Quick Find Active TA Directories (type 4), TA Directories (type 8192), Advanced Find (type 1), Associated (type 2), and Lookup (type 64).
- No app components were added by Phase 2C. The live sitemap table and exported `AppModuleSiteMaps` section identify an app-aware BSO-RS-Support sitemap with unique name `srapp` in Default Solution. No sitemap for an `os_srapp` app is verified. No role assignment or publication change was performed.
- Live `solutioncomponent.componenttype` choice metadata returned 180 options and no entries for `80` or `10091`. The type-80 component row is a root (`rootsolutioncomponentid=null`, `rootcomponentbehavior=0`, `ismetadata=false`) whose `objectid` matches the existing PAC-listed BSO-RS-Support AppModule ID. It is **identified and a confirmed creation conflict**.
- The type-10091 row is a non-metadata child of type 80 (`rootsolutioncomponentid` equals the type-80 solutioncomponentid; `rootcomponentbehavior=0`, `ismetadata=false`). Supported dependency functions show it requires type 80 and type 10094; no dependent components were returned. Type 10094 exists in Default and managed `msdyn_AppFrameworkInfraExtensions` Solution component inventories. `AppModuleSiteMaps` export and live sitemap metadata both reference unique name `srapp`, but the type-10091 object ID does not equal the sitemap ID and no public type mapping was found. Its exact identity is **UNKNOWN**; it is dependency-linked to the existing app, with no separate conflict/corruption demonstrated.
- Microsoft's documented AppModule creation sequence does not require resolving every unrelated Solution component. However, the existing same-display-name AppModule independently conflicts with creation of the approved app shell. No AppModule Create request was sent.
## Naming Proposal and Verification

Installed PAC 2.13.1 `pac model create` exposes display name, description, environment, Solution, and optional publish, but **no technical-name parameter**. It cannot guarantee `os_srapp`; the proposed AppModule API path is required if the technical name is accepted.

Microsoft's [AppModule creation guidance](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code) says the supplied `uniquename` uses English letters and numbers and that Dataverse automatically prepends the Solution Publisher prefix. The AppModule table reference exposes `uniquename` as a writable string (maximum length 100). Thus `srapp` meets the documented input character rule; with prefix `os`, the documented expected final value is `os_srapp`. The Web API/SDK path permits the caller to supply `uniquename`, unlike PAC `model create`.

The live app inventory contains five apps; a direct read-only `appmodule.uniquename` query for `os_srapp` returned no rows, but PAC lists a BSO-RS-Support app with unique name `srapp`. This existing same-display-name app is a confirmed creation conflict even though its unique name differs. The target Solution and Publisher were independently verified. Do not create a second app under the same display name. After owner/admin reconciliation and new direction, any authorized creation must independently read back `appmodule.uniquename`, Publisher, Solution, and publication state. If the final name differs from `os_srapp`, stop; do not rename, delete, recreate, or accept a substitute automatically.

The owner has approved this component-specific exception for the app only. The project-wide `os_sr_*` convention remains unchanged for every other component. This exception does not alter table names, Solution names, or Publisher settings. Actual prefix behavior and final name still require post-create read-back.

The AppModule Create API accepts a unique-name property, and the documented `SolutionUniqueName` parameter can associate a supported Create request with the existing Solution. Any future approved path must independently read back the final `appmodule.uniquename`, Publisher, Solution, and unpublished state before configuring components.

## Component Dependencies

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
