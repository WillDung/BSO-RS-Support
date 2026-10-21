# BSO-RS-Support Model-driven App Manifest

**Status:** Phase 2B naming assessment, 21 October 2026. Documentation only; no app resources were created or modified. The display name and navigation are requested design. The proposed technical name `os_sr_app` is **not supported by the documented AppModule auto-prefix input contract**; no replacement is selected. Runtime rejection/transformation behavior for an underscore-containing suffix is **UNKNOWN**. The separate Phase 1D-D `os_sr_pos` HTTP 401 incident remains **UNKNOWN** and is not resolved by these checks.

## Manifest

```yaml
apiVersion: bso-rs-support/v1
kind: modelDrivenApp
status: proposed
app:
  displayName: BSO-RS-Support
  uniqueName: os_sr_app
  uniqueNameStatus: blocked-by-documented-input-contract
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
      uniqueName: os_sr_app
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
- Four model-driven apps exist: Power Pages Management, Power Platform Environment Settings, Recruitment Candidate Pipeline, and Solution Health Hub. No BSO-RS-Support app and no `os_sr_app` unique name appeared in the inventory. The Recruitment Candidate Pipeline app is associated with another Solution.
- The only project custom table is `os_sr_ta`. Position, Candidate Source, and Location remain absent. No business rows were read.
- The project Solution has one table root component for TA with `rootcomponentbehavior=0` (Include Subcomponents). A temporary PAC unmanaged Solution export contained the TA entity metadata, 3 form components, and 7 saved-query components; the archive was inspected for display/type metadata only and removed.
- TA forms exported: Information (`main`), Information (`card`), and Information (`quick`). TA view inventory: Active TA Directories (public view, query type 0, default); Inactive TA Directories (type 0); Quick Find Active TA Directories (type 4); TA Directories (type 8192); TA Directory Advanced Find View (type 1); TA Directory Associated View (type 2); TA Directory Lookup View (type 64).
- No app-specific sitemap, component selection, role assignment, or publication exists for the proposed app. Existing environment security settings and grants were not changed or evaluated in this app-design phase.

## Naming Decision Gate

Installed PAC 2.13.1 `pac model create` exposes display name, description, environment, Solution, and optional publish, but **no technical-name parameter**. It cannot guarantee `os_sr_app`.

Microsoft's [AppModule creation guidance](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code) says the supplied `uniquename` uses English letters and numbers and that Dataverse automatically prepends the Solution Publisher prefix. The AppModule table reference separately exposes `uniquename` as a writable string (maximum length 100); this confirms the caller supplies a value, not that it can bypass prefixing or naming validation.

With Publisher prefix `os`, producing the exact final `os_sr_app` through the documented behavior would require the caller-supplied suffix `sr_app`. That suffix includes an underscore and does not meet the documented letters-and-numbers input rule. Supplying the full `os_sr_app` to a prefix-aware creation path risks double-prefixing; supplying another stem would silently change the requested name. Therefore `os_sr_app` is **not a supported/guaranteed name under the documented creation contract**. Whether the service accepts or rewrites the underscore is **UNKNOWN**; this phase does not test by creating an app. There is no safe executable exact-name payload until Microsoft documents an exception or the owner explicitly approves a different technical name. Do not substitute one automatically.

The AppModule Create API can accept a unique-name property and the documented `SolutionUniqueName` parameter can associate a supported Create request with the existing Solution. Those capabilities do not override prefixing or the input constraint. Any future approved path must independently read back the final `appmodule.uniquename`, Publisher, Solution, and unpublished state before configuring components.

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
