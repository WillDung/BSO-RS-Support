# Model-driven App and Sitemap Automation Runbook

**Status:** Phase 2A implementation design only, 21 October 2026. No Power Platform resources were changed. Target is the verified VN LMV IT organization and the existing unmanaged Solution `os_sr_bso_rs_support`. The desired app unique name `os_sr_app` remains proposed pending a nonproduction naming check. Do not execute the write templates below as part of this phase.

## Target

- App display name: **BSO-RS-Support**.
- Proposed final unique name: **os_sr_app**; exact publisher-prefix behavior is unresolved. Do not allow automatic double-prefixing.
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
| AppModule SDK/Web API | Create `appmodule` with name, unique name, description and default web resource; use `SolutionUniqueName` on supported Create request/header | AppModule unique name is publisher-prefixed on create. Exact `os_sr_app` behavior is not proven; verify only in approved nonproduction before use. |
| Model-driven app APIs | `AddAppComponents`, `RetrieveAppComponents`, `ValidateApp`, and `PublishXml` | Use typed components/IDs from read-only metadata. Add forms/views only after explicit selection. Validation and publication are separate. |
| AppModuleComponent metadata | Component type values include Entity `1`, View `26`, Form `60`, Sitemap `62` | Use supported app APIs/designer rather than directly creating internal app-module component rows. |
| Forms and views | Dataverse SDK CRUD on `systemform` and `savedquery`; AddAppComponents binds existing components to the app | Do not change approved TA layout/query metadata in this phase. Form XML and FetchXML are not required to add existing components. |
| Sitemap | Supported SiteMap XML component/record and AddAppComponents association; Power Apps app designer is also supported | Use designer-generated, schema-valid SiteMap XML as the source template. Genpage add/upload is for generated pages, not ordinary entity navigation. |
| Dataverse MCP | Current session supports metadata schema descriptions, selected metadata SQL reads, and Solution export via PAC | No dedicated model-driven app composition tool was exposed. The generic Custom API invoker is not a generic caller for every standard action. Metadata SQL did not successfully return TA systemform/savedquery records; export was used to inspect Solution metadata. |
| Official skills | `dv-connect`, `dv-metadata`, `dv-solution`, and `dv-security` are present in `.agents/skills` | `dv-metadata` covers schema/forms/views; `dv-solution` covers ALM; `dv-security` covers access. None provides a complete app shell + sitemap deployment workflow. |

## Read-only Preflight

Run these before any future write. Stop on any target mismatch; never switch environments.

```powershell
$org = 'https://org14938ec2.crm4.dynamics.com'
pac env who
pac solution list --environment $org
pac model list --environment $org
pac model list-tables --environment $org --type custom --search os_sr_ta,os_sr_pos,os_sr_csrc,os_sr_loc
```

The expected identity is VN LMV IT and the URL above. Verify Publisher prefix `os`, target Solution unique name/version/Publisher, the selected app name is not already present, and only expected project tables exist. Confirm TA form/view IDs and metadata with a read-only Dataverse SDK/Web API query or temporary PAC Solution export. Do not read table rows. Do not invoke the failed Position metadata operation.

For Solution membership, use PAC `solution list`, read-only `solutioncomponent` queries, `RetrieveAppComponents` for the app after it exists, and an export read-back. A TA table root component with `rootcomponentbehavior=0` includes its table subcomponents in the Solution; the app’s own component selection is separate.

## Naming Gate

Installed command help:

```text
pac model create [--environment] --name [--description] [--solution] [--publish]
```

There is no `--unique-name` option. This command can associate the app with the Solution but cannot guarantee `os_sr_app`.

Microsoft documents AppModule `uniquename` as publisher-prefixed at creation and the supplied unique-name text as English letters and numbers. The desired suffix `sr_app` contains an underscore. Do not guess that the service accepts it, supply `os_sr_app` to an auto-prefixing input, or infer a name from the display name. First obtain an approved disposable nonproduction environment and run a controlled create/read-back naming test there, or verify an exact supported naming pattern with Microsoft. Do not perform this experiment in VN LMV IT Production.

After the naming test, use the supported AppModule `Create` request with the verified prefix-free value and `SolutionUniqueName: os_sr_bso_rs_support` (SDK request parameter or Web API optional-parameter header). The documented default icon web resource is `953b9fac-1e5e-e611-80d6-00155ded156f`; confirm availability or use an approved existing icon. Read back `appmoduleid`, `name`, `uniquename`, `publisherid`, `solutionid`, `statecode`, and `componentstate`. Continue only if final `uniquename` is exactly `os_sr_app`, publisher and Solution are exact, and the app is unpublished. If unexpected, stop; do not rename, delete, or recreate.

Review-only PAC command (creates an app if executed; not run and not guaranteed to produce the proposed unique name):

```powershell
pac model create `
  --environment 'https://org14938ec2.crm4.dynamics.com' `
  --name 'BSO-RS-Support' `
  --description 'Internal recruitment support application for authorized BSO candidate operations, backed by Dataverse.' `
  --solution 'os_sr_bso_rs_support'
```

Do not add `--publish`. PAC is suitable only if the owner accepts the generated unique name after read-back; otherwise use the verified AppModule path after the naming gate.

## App Composition Sequence

Every write step below is a future phase requiring its own explicit authorization. The automation should default to plan/read-only mode and require an explicit Apply switch plus typed confirmation for each authorized change batch.

1. **Create unpublished AppModule.** Use PAC only if its generated technical name is acceptable and confirmed. For exact-name control, use the supported AppModule Create API after the naming gate. Set the target `SolutionUniqueName`; omit publishing. Stop on any failure.
2. **Verify app identity and Solution.** Independently read the AppModule row and Solution component membership. Confirm exact display/unique names, Publisher, Solution, app state, and unpublished component state. Do not proceed on mismatch.
3. **Add TA table component.** Resolve the TA metadata ID with a GET and use the documented `AddAppComponents` action (or app designer) for the `os_sr_ta` table component. Read back `RetrieveAppComponents` and app component membership. No record/table data access.
4. **Configure sitemap.** Build an app sitemap with Area `Recruitment Support`, Group `Administration`, and entity SubArea `TA Directory` targeting `os_sr_ta`. Use the supported SiteMap component/app APIs or Power Apps app designer and a schema-valid sitemap generated from a supported template. Associate the sitemap with the app (Sitemap component type `62`) and read it back. `pac model genpage add` only attaches a generated page and cannot create this ordinary table SubArea.
5. **Select existing UI components.** Resolve current TA form/view GUIDs and published status using read-only metadata. Add only the Main form (`Information`) and default public view (`Active TA Directories`) through `AddAppComponents`; the documented app component types are Form `60` and View `26`. Verify the actual app component list. Do not modify the form, views, TA metadata, or application-wide defaults.
6. **Validate dependencies.** Call `ValidateApp(AppModuleId=<verified app GUID>)` and review the full `ValidationIssueList`. Confirm required sitemap, table, form, view, and Solution membership. Verify security dependencies without changing roles; app access remains unavailable until a separate security approval and assignment.
7. **Pause unpublished.** Keep the app unpublished until a separate release approval. After approval only, publish with the app-scoped `PublishXml` action, read back published state/components, and complete user/accessibility/UAT checks.
8. **ALM read-back.** Export/unpack the Solution using PAC to an approved local path, compare the app, sitemap, table reference, selected forms/views, and dependencies against this manifest. Do not commit/push/sync; Git remains owner-controlled.

## API Operation References

Use supported Microsoft actions and SDK request types; do not handcraft opaque internal app graph data:

- Create AppModule row: `POST /api/data/v9.2/appmodules`, with the `MSCRM.SolutionUniqueName` optional parameter.
- Add selected app components: `POST /api/data/v9.2/AddAppComponents` with `AppId` and typed `Components`; Microsoft examples include `savedquery` and `systemform`. The action documentation also lists sitemap, entity, dashboard, and business-process-flow components.
- Read app selection: `GET /api/data/v9.2/RetrieveAppComponents(AppModuleId=<GUID>)`.
- Validate: `GET /api/data/v9.2/ValidateApp(AppModuleId=<GUID>)`.
- Publish only after separate approval: `POST /api/data/v9.2/PublishXml` with only the target app ID in `<appmodules>`.

For standard forms/views, the `dv-metadata` skill documents `systemform` and `savedquery` SDK record CRUD. The app designer/API selection of those existing records is distinct from creating or editing them.

## Failure and Recovery

- Stop after the first failed or ambiguous write. Do not automatically retry.
- Read back AppModule, Solution membership, app component list, sitemap, and selected forms/views before proposing any follow-up.
- If an object exists but is incomplete, preserve it and report the partial state. No automatic delete, rename, recreate, or publish.
- No table creation, business-row access, security-role changes, audit changes, environment switch, or Git operation is part of this app phase.
- Keep the Phase 1D-D Position 401 separate. Its cause remains **UNKNOWN**; successful GETs or app creation do not resolve it. Do not retry Position.

## References

- [App Manifest](MODEL_DRIVEN_APP_MANIFEST.md)
- [VS Code Power Platform Autobuild](VS_CODE_POWER_PLATFORM_AUTOBUILD.md)
- [Current State](CURRENT_STATE.md)
- [PAC model command reference](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/model)
- [Create, manage, and publish model-driven apps using code](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code)
- [AddAppComponents](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/addappcomponents)
- [AppModuleComponent](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/appmodulecomponent)
- [Use optional parameters](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/optional-parameters)
