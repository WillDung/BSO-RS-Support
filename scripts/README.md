# Scripts

Scripts here support reviewed build, validation, migration, and ALM tasks. They must be safe by default, avoid embedded credentials and personal data, clearly identify environment effects, and include verification instructions.

## TA Reference Table Provisioning

[Provision-BsoRsTaTable.ps1](Provision-BsoRsTaTable.ps1) implements the reviewed metadata payload for only `os_sr_ta`; `TA Directories` remains a proposed collection label, not an approved requirement. It uses the official Dataverse Web API, verifies environment/Publisher/Solution before any write, associates metadata using `MSCRM.SolutionUniqueName`, and reads back the result. It does not access table rows or create records.

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

The API requires `DisplayCollectionName`, while the approved schema specifies only `TA Directory`. The preview derives `TA Directories` as a proposed plural label. This is not an approved business requirement; obtain owner confirmation before Apply.

### Online DryRun

After installing the documented prerequisites through the approved IT process and setting the required process-scoped environment variables, run the authenticated read-only DryRun:

```powershell
& (Join-Path $PWD 'scripts/Provision-BsoRsTaTable.ps1')
```

The script first validates the active environment, signs in interactively only when Az has no authorized tenant context, obtains a Dataverse-resource token as SecureString, and uses GET requests only. It verifies WhoAmI, Publisher, Solution, audit baseline, target/project table absence, and the proposed metadata payload. It performs no Web API write methods. Treat displayed environment URL and IDs as sensitive operational configuration; do not save output in this repository. Never add `-Apply` to this command.

Authenticated DryRun on 19 October 2026 passed using PowerShell 7.6.7 and Az.Accounts 5.5.3. The authorized Az tenant/user and PAC environment matched; Dataverse accepted the organization-resource token. WhoAmI matched the expected organization and Dataverse user. The Publisher prefix was `os`; the unmanaged Solution was version `1.0.0.0` and linked to that Publisher. No `os_sr_*` table definitions existed, including `os_sr_ta`. The script returned `DryRunPassed` with `WritesPerformed: 0`; no business records were accessed and no audit setting was changed. This is read-only readiness evidence, not approval or validation of Apply. `TA Directories` remains a proposed label.

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

### Apply Command (Not Authorized or Executed)

Only after separate explicit approval and approval of the derived collection label:

```powershell
& (Join-Path $PWD 'scripts/Provision-BsoRsTaTable.ps1') -Apply -DisplayCollectionName 'TA Directories'
```

Apply requires typing `CREATE os_sr_ta IN VN LMV IT WITH COLLECTION TA Directories`. It creates the table and primary name, creates TA Email, publishes only that table metadata, then verifies ownership, names/types/requiredness, standard state/status fields, keys, Solution membership, audit settings, and project-table inventory. An uncertain write triggers read-only reconciliation; the script never retries or deletes/recreates automatically. No Apply operation has been performed.

See [Phase 1D-B runbook](../docs/PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md), [Dataverse Schema Specification](../docs/DATAVERSE_SCHEMA_SPECIFICATION.md), and [ALM and Deployment](../docs/ALM_DEPLOYMENT.md).
