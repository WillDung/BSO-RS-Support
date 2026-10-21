# Model-driven App and Sitemap Automation Runbook

**Status:** Phase 2C-R2 adoption assessment, 21 October 2026. The existing BSO-RS-Support AppModule (`srapp`) is active but unpublished, has no app-component associations or usable navigation found, and is associated with System Administrator/System Customizer roles. The AppModule's own Publisher lookup was not returned and remains unverified. Classification: **B, suitable only after approved changes**. Adoption is not authorized. Do not create, rename, delete, modify, or publish this app.

## Target

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

## Read-only Preflight

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

## Approved Name and Held Request

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

## App Composition Sequence

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
- Phase 2C-R2 read-only outcome: AppModule ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`, unique name `srapp`, display name BSO-RS-Support. `RetrieveUnpublished` reports Active state and `componentstate=1`; the published row is absent. The app has no appmodulecomponent rows, empty appgraph/configxml, a Published but blank placeholder sitemap, and two app-role associations (System Administrator and System Customizer). Type 10091 is not the sitemap object ID; it depends on the AppModule and a separate type-10094 component, while its exact identity remains unknown. Classification is B, conditional on owner-approved naming, navigation/component/security changes and type-10091 review. Adoption is not authorized. No Dataverse writes or business-row reads occurred.

## References

- [App Manifest](MODEL_DRIVEN_APP_MANIFEST.md)
- [VS Code Power Platform Autobuild](VS_CODE_POWER_PLATFORM_AUTOBUILD.md)
- [Current State](CURRENT_STATE.md)
- [PAC model command reference](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/model)
- [Create, manage, and publish model-driven apps using code](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code)
- [AddAppComponents](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/addappcomponents)
- [RetrieveAppComponents](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrieveappcomponents)
- [RetrieveUnpublished](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrieveunpublished)
- [AppModuleComponent](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/appmodulecomponent)
- [Use optional parameters](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/optional-parameters)
