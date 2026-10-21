# BSO-RS-Support Model-driven App Manifest

**Status:** Phase 2C naming approved; creation preflight blocked, 21 October 2026. The project owner explicitly approved exactly one unpublished AppModule with caller suffix `srapp`, expected final `os_srapp`, as an app-only exception to `os_sr_*`. No app resource was created. Two unexplained Solution-component root types block the write. The separate Phase 1D-D `os_sr_pos` HTTP 401 incident remains **UNKNOWN** and is not resolved by this app work.

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

- PAC active organization is VN LMV IT at the requested organization URL; its environment and organization identity matched the project baseline.
- Publisher `os_bso_rs_support` has prefix `os`; Solution `os_sr_bso_rs_support` is unmanaged version `1.0.0.0` and linked to that Publisher.
- Four model-driven apps exist: Power Pages Management, Power Platform Environment Settings, Recruitment Candidate Pipeline, and Solution Health Hub. No BSO-RS-Support app or `os_srapp` unique name appeared in the inventory. A direct read-only AppModule query for `os_srapp` returned no rows. The Recruitment Candidate Pipeline app is associated with another Solution.
- The only project custom table is `os_sr_ta`. Position, Candidate Source, and Location remain absent. No business rows were read.
- The project Solution has one table root component for TA with `rootcomponentbehavior=0` (Include Subcomponents). A temporary PAC unmanaged Solution export contained the TA entity metadata, 3 form components, and 7 saved-query components; the archive was inspected for display/type metadata only and removed.
- TA forms exported: Information (`main`), Information (`card`), and Information (`quick`). TA view inventory: Active TA Directories (public view, query type 0, default); Inactive TA Directories (type 0); Quick Find Active TA Directories (type 4); TA Directories (type 8192); TA Directory Advanced Find View (type 1); TA Directory Associated View (type 2); TA Directory Lookup View (type 64).
- No app-specific sitemap, component selection, role assignment, or publication exists for the proposed app. Existing environment security settings and grants were not changed or evaluated in this app-design phase.
- Phase 2C preflight found two additional root rows in the target Solution component query with component types `80` and `10091`. These values are absent from the published `solutioncomponent.componenttype` choices. Direct AppModule/AppModuleComponent lookups did not identify their object IDs, and a temporary read-only Solution export contained zero AppModule sections. Their origin and meaning are **UNKNOWN**. The AppModule Create request was not issued.

## Naming Proposal and Verification

Installed PAC 2.13.1 `pac model create` exposes display name, description, environment, Solution, and optional publish, but **no technical-name parameter**. It cannot guarantee `os_srapp`; the proposed AppModule API path is required if the technical name is accepted.

Microsoft's [AppModule creation guidance](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code) says the supplied `uniquename` uses English letters and numbers and that Dataverse automatically prepends the Solution Publisher prefix. The AppModule table reference exposes `uniquename` as a writable string (maximum length 100). Thus `srapp` meets the documented input character rule; with prefix `os`, the documented expected final value is `os_srapp`. The Web API/SDK path permits the caller to supply `uniquename`, unlike PAC `model create`.

The live app inventory contains four apps and no `os_srapp`; a direct read-only `appmodule.uniquename` query for `os_srapp` returned no rows. The target Solution and Publisher were independently verified. This is an absence/collision check only; no create request was sent. After any separately authorized creation, read back `appmodule.uniquename`, Publisher, Solution, and publication state. If the final name differs from `os_srapp`, stop; do not rename, delete, recreate, or accept a substitute automatically.

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
| Sitemap | No app-specific sitemap exists for the proposed app | Create/configure Area > Group > SubArea, attach to app, then read back and validate |
| App access | No app-specific role association exists | Requires a later security review and separate approval; do not assign roles in Phase 2A |

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
