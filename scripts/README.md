# Scripts

Scripts here support reviewed build, validation, migration, and ALM tasks. They must be safe by default, avoid embedded credentials and personal data, clearly identify environment effects, and include verification instructions.

## TA Reference Table Provisioning

[Provision-BsoRsTaTable.ps1](Provision-BsoRsTaTable.ps1) implements the approved metadata payload for only `os_sr_ta`. It uses the official Dataverse Web API, verifies environment/Publisher/Solution before any write, associates metadata using `MSCRM.SolutionUniqueName`, and reads back the result. It does not access table rows or create records.

The default mode is online **DryRun** (interactive auth plus read-only preflight). `-PlanOnly` prints and locally validates the payload without authentication or network calls. Only `-Apply` reaches metadata POST operations; it also requires a typed confirmation phrase. Never use Apply without separate explicit approval.

### Interactive Authentication Prerequisites

The script uses Microsoft.Identity.Client (MSAL) interactive delegated authentication; it does not read PAC token-cache files, scrape browser sessions, or use a client secret. IT must provide:

- An approved Entra public-client app registration with delegated Dataverse `user_impersonation` permission and required consent.
- A registered loopback redirect URI `http://localhost`, matching the script configuration. MFA and Conditional Access remain enforced.
- An IT-approved `Microsoft.Identity.Client.dll` compatible with the installed PowerShell/.NET runtime. Set `BSO_RS_MSAL_ASSEMBLY` to its local path; the script does not install or download packages.
- The app registration Client ID in process environment variable `BSO_RS_DATAVERSE_CLIENT_ID`.
- Process-scoped `BSO_RS_ENVIRONMENT_NAME`, `BSO_RS_ORG_URL`, `BSO_RS_EXPECTED_ENVIRONMENT_ID`, and `BSO_RS_EXPECTED_ORG_ID` values. The script independently checks `pac env who` and Dataverse `WhoAmI`; it does not switch environments.
- A caller identity with the required Dataverse metadata customization and Solution privileges, typically System Customizer or equivalent. The script does not elevate roles.

Do not store the app Client ID, live URL, environment/org IDs, or credentials in this repository. The Client ID is configuration, not a secret; tokens remain in process memory only. If the app registration or MSAL assembly is not available, use `-PlanOnly` and stop before online DryRun/Apply.

### Offline Preview

```powershell
& (Join-Path $PWD 'scripts/Provision-BsoRsTaTable.ps1') -PlanOnly -EnvironmentName 'VN LMV IT' -OrganizationUrl '<approved-org-url>' -ExpectedEnvironmentId '<approved-environment-id>' -ExpectedOrganizationId '<approved-organization-id>'
```

The API requires `DisplayCollectionName`, while the approved schema specifies only `TA Directory`. The preview derives `TA Directories` as a proposed plural label. This is not an approved business requirement; obtain owner confirmation before Apply.

### Online DryRun

After setting the required process-scoped environment variables and MSAL assembly path, invoke the script with no `-Apply` switch:

```powershell
& (Join-Path $PWD 'scripts/Provision-BsoRsTaTable.ps1')
```

DryRun performs only GET requests and prints a sanitized plan. It stops on any environment, Publisher, Solution, audit-baseline, table-existence, or unexpected `os_sr_*` metadata mismatch.

### Apply Command (Not Authorized or Executed)

Only after separate explicit approval and approval of the derived collection label:

```powershell
& (Join-Path $PWD 'scripts/Provision-BsoRsTaTable.ps1') -Apply -DisplayCollectionName 'TA Directories'
```

Apply requires typing `CREATE os_sr_ta IN VN LMV IT WITH COLLECTION TA Directories`. It creates the table and primary name, creates TA Email, publishes only that table metadata, then verifies ownership, names/types/requiredness, standard state/status fields, keys, Solution membership, audit settings, and project-table inventory. An uncertain write triggers read-only reconciliation; the script never retries or deletes/recreates automatically. No Apply operation has been performed.

See [Phase 1D-B runbook](../docs/PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md), [Dataverse Schema Specification](../docs/DATAVERSE_SCHEMA_SPECIFICATION.md), and [ALM and Deployment](../docs/ALM_DEPLOYMENT.md).
