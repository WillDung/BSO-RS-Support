# Scripts

Scripts here support reviewed build, validation, migration, and ALM tasks. They must be safe by default, avoid embedded credentials and personal data, clearly identify environment effects, and include verification instructions.

## Reference Table Provisioning

[Provision-BsoRsTaTable.ps1](Provision-BsoRsTaTable.ps1) is the shared reference-table provisioner; its filename and default `os_sr_ta` selection remain for backward compatibility. [ReferenceTableDefinitions.psd1](ReferenceTableDefinitions.psd1) declares TA and three reference schemas. `-TableName` selects exactly one of `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, or `os_sr_loc`. The owner approved Phase 1D-D Apply and the three plural labels on 20 October 2026. The first Position Apply attempt returned HTTP 401 at the first metadata POST; immediate read-only reconciliation found no Position metadata. The script stopped; Candidate Source and Location Apply were not attempted. Do not rerun Apply or continue the sequence until the 401 is resolved and a recovery decision is recorded. TA remains the only project table.

The default mode is online **DryRun** (interactive auth plus read-only preflight). `-PlanOnly` prints and locally validates the payload without authentication or network calls. Only `-Apply` reaches metadata POST operations; it also requires a typed confirmation phrase. Never use Apply without separate explicit approval.

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

Historical Phase 1D-C and Phase 1D-D read-only checks passed using PowerShell 7.6.7 and Az.Accounts 5.5.3. On 20 October 2026, the approved Position Apply reached one `POST EntityDefinitions` attempt and returned `401 Unauthorized`; reconciliation found Position absent. No subsequent POST, other-table Apply, retry, deletion, or recreation occurred. Read-only effective-privilege checks returned Global depth for `prvCreateEntity`, `prvCreateAttribute`, `prvCreateCustomization`, and `prvPublishCustomization`. The Az identity and same-invocation GETs succeeded. **Root cause remains UNKNOWN:** the failed execution did not capture the response body/error code, `WWW-Authenticate`, request/correlation IDs, POST timestamp, or token issuance/expiry claims.

The successful TA flow and failed Position flow used the same token-before-preflight / typed-prompt / POST ordering, bearer Authorization construction, JSON Content-Type, `If-None-Match`, and `MSCRM.SolutionUniqueName` header. Transcript timing puts confirmation and the returned failure within seconds; the historical token expiry is unavailable, so expiry cannot be conclusively ruled in or out, though no evidence supports expiry. The current helper validates Dataverse audience/tenant/scope/expiry and refreshes through Az.Accounts before a request when under five minutes remain, including after confirmation. It records only sanitized status, error code/message, allowlisted challenge scheme/error, request/correlation IDs, path, request start, and token timestamps. It never logs a token or full headers. This is preventive hardening, not a confirmed fix for the historical 401. See [Current State](../docs/CURRENT_STATE.md). Do not retry or bypass policy.

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
