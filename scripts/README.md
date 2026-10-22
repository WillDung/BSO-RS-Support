# Scripts

Scripts here support reviewed build, validation, migration, and ALM tasks. They must be safe by default, avoid embedded credentials and personal data, clearly identify environment effects, and include verification instructions.

## VS Code Readiness

[Test-BsoVsCodeReadiness.ps1](Test-BsoVsCodeReadiness.ps1) performs local tool checks and read-only PAC environment/Solution checks. Its PAC app-authoring capability result is based on the `create` entry in successful `pac model help` output, not the literal phrase `model create`. Run the synthetic parser regression checks with `& ./tests/ReadinessChecks.Tests.ps1`; they do not invoke PAC or contact an environment.

The script separately reports MCP configuration presence, runtime config source, discovery, callability, permission scope, wildcard tool selection, environment-specific endpoint presence, and skill-lock path alignment. Configuration presence is not treated as proof of a working server; endpoint values are never printed. During Sprint 02B inspection, root `.mcp.json` declared two servers with wildcard tool selection and an environment-specific HTTP endpoint, while `.vscode/mcp.json` had an empty `servers` object. VS Code log records from 20-21 October 2026 reported that PAC MCP was unsupported by the installed CLI and Dataverse authorization-server metadata discovery returned 404. The current VS Code MCP runtime source is **UNKNOWN**; neither server was started or called in Sprint 02B. Both configuration files are preserved because the supported configuration source/installer contract could not be proven. Do not add endpoint values to tracked files or infer read-only tool permissions from configuration.

The `skills-lock.json` entries point to `.github/plugins/dataverse/skills`, which does not exist in this workspace. The corresponding nine skill files are under `.agents/skills`; five project skills are under `.github/skills`. No duplicate skill directory names were found across those roots. Whether the lockfile belongs to a separate plugin installer and whether Copilot discovers each local directory are **UNKNOWN**. The readiness check reports path mismatch but does not rewrite the lockfile or reinstall skills.

## Reference Table Provisioning

[Provision-BsoRsTaTable.ps1](Provision-BsoRsTaTable.ps1) is the shared reference-table provisioner; its filename and default `os_sr_ta` selection remain for backward compatibility. [ReferenceTableDefinitions.psd1](ReferenceTableDefinitions.psd1) declares TA and three reference schemas. `-TableName` selects exactly one of `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, or `os_sr_loc`. The owner approved Phase 1D-D Apply and the three plural labels on 20 October 2026. The first Position Apply attempt returned HTTP 401 at the first metadata POST; its immediate read-only reconciliation found no Position metadata. A separate, single owner-authorized Sprint 02C recovery POST later had an unavailable status and an immediate GET reconciliation reported absent. Sprint 02C.1 then performed fresh GET-only reconciliation and verified the exact Position metadata and Solution membership. Do not retry, recreate, or run the recovery mode: Position now exists. Candidate Source and Location Apply were not attempted.

The default mode is online **DryRun** (interactive auth plus read-only preflight). `-PlanOnly` prints and locally validates the payload without authentication or network calls. Metadata POSTs are available only through `-Apply` or a specifically guarded bounded mode; each write mode requires typed confirmation. Never use Apply without separate explicit approval.

### Sprint 02D Bounded Modes

`-CreateOnlyCandidateSource` is restricted to `os_sr_csrc`. It verifies the exact PlanOnly payload fingerprint, requires Position to be verified published, requires the process-scoped `BSO_RS_EXPECTED_USER_ID` to match PAC, requires the expected `os_sr_ta`/`os_sr_pos` inventory and no unmapped Entity/Attribute Solution components, then permits at most one `POST EntityDefinitions` with the Solution header. It performs GET-only reconciliation, fixes `MaximumRetryCount` at zero, and never publishes automatically. Candidate Source publication, if separately proven necessary, uses `-PublishOnly -TableName os_sr_csrc`.

`-PublishOnly` is restricted to Position or Candidate Source and permits at most one table-scoped `POST PublishXml`. It requires a fresh preflight and a `RetrieveEntity` comparison showing either `PUBLISHED_WITH_UNPUBLISHED_DELTA` or `UNPUBLISHED_ONLY`; `PUBLISHED_NO_PENDING_DELTA` is left unchanged, and `UNKNOWN` blocks without a write. The mode requires only the effective publish privilege and cannot create or alter schema.

Publication detection uses Microsoft's [RetrieveEntity Web API function](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrieveentity?view=dataverse-latest) twice (`RetrieveAsIfPublished=false` and `true`) and compares normalized schema metadata. It does not infer publication from `solutioncomponents.componentstate`. The classifications are `PUBLISHED_NO_PENDING_DELTA`, `PUBLISHED_WITH_UNPUBLISHED_DELTA`, `UNPUBLISHED_ONLY`, and `UNKNOWN`; failed or malformed retrievals fail closed as `UNKNOWN`. `-VerifyPublicationOnly` is restricted to Position and Candidate Source and runs the comparison after read-only identity, Solution, Publisher, inventory, table, and membership checks. It permits GET only and sets `MaximumRetryCount` to zero. Bounded-create results include request counts; see [Current State](../docs/CURRENT_STATE.md) for Sprint 02E's one-time count-retention gap and observed outcome.

### Sprint 02F Controlled Location Mode

`-CreateOnlyLocation -TableName os_sr_loc -DisplayCollectionName Locations` is restricted to the Location reference table and its approved three payloads. It requires the expected-user process guard, PAC/Az/WhoAmI identity agreement, the approved VN LMV IT environment and unmanaged Solution/Publisher, the exact TA/Position/Candidate Source inventory, Location absence, mapped Solution components, and create privileges. It also requires a safe external authorization reference and typed confirmation.

The mode recomputes SHA-256 fingerprints before dispatch for the Location table payload, Room/Resource Email attribute, and Location Details attribute. It permits only this order: one `POST EntityDefinitions`, one Room/Resource Email attribute POST, then one Location Details attribute POST. Each write has `MaximumRetryCount=0`; each response is independently reconciled with GET-only metadata and Solution-membership reads carrying `Consistency: Strong`. A missing or partial read-back stops the sequence without retry. After the final column it verifies the full schema, inventory, Solution component mapping, unchanged audit settings, and published versus as-if-published metadata. It never calls `PublishXml`, PATCH, DELETE, or business-data endpoints.

Generic `-Apply` is disabled for Location so it cannot take the broader publish-after-create path. Strong consistency is applied only to bounded Location post-write metadata read-back and final verification requests. It does not alter HTTP response classification or authorize retries. `-PlanOnly -TableName os_sr_loc` remains offline and reports the three payload fingerprints.

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

Historical Phase 1D-C and Phase 1D-D read-only checks passed using PowerShell 7.6.7 and Az.Accounts 5.5.3. On 20 October 2026, the approved Position Apply reached one `POST EntityDefinitions` attempt and returned `401 Unauthorized`; immediate reconciliation found Position absent. A separately authorized Sprint 02C recovery later dispatched one POST; its sanitized summary retained no HTTP status, error code, or request/correlation IDs and immediate reconciliation reported absent. The 02C.1 live read now verifies exact Position metadata and Solution membership. No further retry, deletion, recreation, or other-table Apply occurred in 02C.1. Read-only effective-privilege checks for the earlier run returned Global depth for `prvCreateEntity`, `prvCreateAttribute`, `prvCreateCustomization`, and `prvPublishCustomization`. **The original 401 root cause and the Sprint 02C response details remain unavailable; do not reconstruct them.**

The successful TA flow and failed Position flow used the same token-before-preflight / typed-prompt / POST ordering, bearer Authorization construction, JSON Content-Type, `If-None-Match`, and `MSCRM.SolutionUniqueName` header. Transcript timing puts the first confirmation and returned failure within seconds; the historical token expiry is unavailable, so expiry cannot be conclusively ruled in or out. The helper validates Dataverse audience/tenant/scope/expiry and refreshes through Az.Accounts before a request when under five minutes remain, including after confirmation. Sprint 02C.1 additionally preserves safe diagnostics on HTTP exceptions: status (or explicit `UNKNOWN`), error classification, allowlisted error code and challenge properties, validated request/correlation GUIDs, relative path, exception category, and dispatch/write Booleans. It never serializes a token, full headers, or raw response body. These changes cannot recover prior response details or prove the original 401 cause. See [Current State](../docs/CURRENT_STATE.md). Do not retry or bypass policy.

### Controlled Position Recovery (Single Authorized Attempt Already Used)

Sprint 02B.1 added an explicit `-CreateOnlyRecovery` mode for `os_sr_pos`. It was invoked once under Sprint 02C owner authorization and must not be run again: Sprint 02C.1 now verifies Position exists exactly and belongs to the project Solution. The original one-attempt authorization is consumed and does not authorize another write. The remaining procedure below records the safeguards used for that attempt; it is not an executable recommendation. No step permits switching environments, identities, authentication mechanisms, or APIs to work around a failure.

**Preconditions**

1. The project owner and the responsible VN LMV IT environment/Dataverse administrator approve one controlled recovery attempt in writing, including the Production-class development target and the exact `os_sr_pos` operation. If the failure requires a privilege or policy change, stop for its own formal security approval; this procedure does not authorize such a change.
2. Set the existing process-scoped environment values for VN LMV IT and `BSO_RS_EXPECTED_USER_ID` to administrator-verified values. The mode checks PAC against the expected environment/organization and user IDs, and checks the existing Az user against PAC without emitting the identity. It will not trigger `Connect-AzAccount`, switch profiles, change identity, or print the configured URL/IDs.
3. Read-only preflight independently confirms `os_sr_pos` is absent from `EntityDefinitions`, the current project inventory is exactly `os_sr_ta`, and every Entity/Attribute component in the project Solution maps to currently verified project metadata. Any unidentifiable Entity or Attribute component blocks recovery. Reconfirm the `os_bso_rs_support` Publisher (`os` prefix), unmanaged `os_sr_bso_rs_support` Solution, and effective `prvCreateEntity`, `prvCreateAttribute`, and `prvCreateCustomization` privileges. `prvPublishCustomization` is not required because this mode cannot publish.
4. The mode recalculates the PlanOnly table payload SHA-256 before authentication and compares it to the approved fingerprint below. It blocks before authentication if the hash differs. It also validates the exact declared Position schema; no additional columns, keys, relationships, audit flags, or data rows are planned.
5. Invoke only the dedicated mode, never `-Apply`:

   ```powershell
   & ./scripts/Provision-BsoRsTaTable.ps1 -CreateOnlyRecovery -TableName os_sr_pos -DisplayCollectionName 'Positions' -AuthorizationReference '<approved-change-reference>'
   ```

   The reference must identify a separately approved operational authorization and match the mode's restricted safe-character syntax. The script then requires the exact typed phrase `RECOVER CREATE os_sr_pos IN VN LMV IT AUTHORIZATION <approved-change-reference>`. Neither a reference string nor typed confirmation proves external approval; the project owner and environment administrator must confirm that approval independently. The existing `-Apply` sequence remains unchanged and is **not suitable** for this one-POST recovery because it posts additional attributes and calls table-scoped `PublishXml`.

**Single intended request**

- Method and target: one `POST` to the configured, verified organization's `/api/data/v9.2/EntityDefinitions` endpoint. Do not substitute MCP `create_table`, PAC, another endpoint, or another identity.
- Body: the exact PlanOnly-validated `Microsoft.Dynamics.CRM.EntityMetadata` payload for `os_sr_pos`, including only the approved table metadata and primary-name attribute.
- Authentication: the existing Az.Accounts user token requested for the configured Dataverse organization resource. The same user must match PAC. Validate tenant, audience, delegated `user_impersonation` scope, and expiry in memory; never output or persist the token or raw claims.
- Headers: bearer credential header (never logged), JSON content type, Accept JSON, OData 4.0 version headers, `If-None-Match: null`, and `MSCRM.SolutionUniqueName: os_sr_bso_rs_support`. Require HTTPS, the verified organization API origin, and redirects disabled.
- Privileges: recovery preflight requests the effective `prvCreateEntity`, `prvCreateAttribute`, and `prvCreateCustomization` set for the existing PAC/Az identity. Missing or unavailable privilege evidence blocks the write. No privilege is granted or changed. `prvPublishCustomization` is deliberately not checked because publishing is prohibited.
- Response: treat only a 2xx response as transport success, not proof of a complete deployment. The exact historical response code and body are unavailable. Independently read back the table and Solution membership before any next operation.

**Sanitized evidence to retain for this one attempt**

The local mode emits the UTC attempt timestamp; environment and identity match Booleans; verified privilege names; state and state-transition timestamps; expected/actual payload hashes; response class/status; allowlisted Dataverse error code and safe summary; validated request/correlation GUIDs; reconciliation result; and whether a write may have occurred. Authentication tenant/audience/scope/expiry are validated in memory by the existing token helper and are not emitted as claims. Never retain Authorization or other full headers, raw token/claims, full response body, credentials, user email, or unfiltered exception text.

**Stop, outcome handling, and reconciliation**

- **401:** stop all writes and reconcile by GET only. Preserve sanitized diagnostics. Have the authorized administrator investigate identity membership, Conditional Access, token audience/scope/expiry, and the challenge using approved logs. Do not refresh into a different identity, switch auth surface, or retry.
- **403:** stop all writes and reconcile by GET only. Request an administrator review of effective privileges and policy; do not self-elevate or retry after a privilege change without a separately approved plan.
- **Deterministic request/schema 4xx other than 408/429:** stop and inspect the sanitized error. Do not assume the metadata write did not occur; reconcile by GET before any recovery decision.
- **408, 429, 5xx, transport error, or timeout:** treat the write outcome as uncertain. Do not automatically retry. Reconcile table metadata and Solution membership using GET-only reads, including whether the table, primary column, or Solution component partially exists.
- **Any 2xx:** issue no subsequent write until independent read-back verifies the exact table schema, generated primary ID/name, absence of unintended metadata, and project Solution root membership. Only a separate authorization may proceed to the next table.
- **Partial or uncertain state:** the provisioner intentionally has no resume, delete, recreate, or automatic repair route. Preserve observed state and prepare a separately reviewed recovery plan. Do not delete or recreate the table; its name and ownership are durable creation-time decisions.

The later `os_sr_csrc` and `os_sr_loc` tasks are independent schemas but remain serialized behind Position recovery by the approved runbook sequence. They require their own fresh preflight and explicit authorization; neither is implicitly authorized by a successful Position recovery. See [Current State](../docs/CURRENT_STATE.md) and [Phase 1D-B Reference Table Runbook](../docs/PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md).

#### One-Attempt State Machine (Implemented Locally)

```text
PRECHECK --all local/external gates and exact payload hash pass--> READY
PRECHECK --any mismatch/unknown required fact/approval missing--> BLOCKED
PRECHECK --payload fingerprint mismatch--> FAILED_VALIDATION
READY --one guarded POST EntityDefinitions--> WRITE_ATTEMPTED
WRITE_ATTEMPTED --any response/transport result--> RECONCILING (GET only)
RECONCILING --exact schema and Solution membership--> VERIFIED_SUCCESS
RECONCILING --unexpected/partial metadata--> PARTIAL_STATE
RECONCILING --401 with no exact table--> FAILED_AUTH
RECONCILING --403 with no exact table--> FAILED_AUTHZ
RECONCILING --deterministic request/schema 4xx with no exact table--> FAILED_VALIDATION
RECONCILING --429/408/5xx/timeout/transport ambiguity or unknown read-back--> UNCERTAIN
```

All outcomes after WRITE_ATTEMPTED permit only GET reconciliation. `Invoke-RestMethod -MaximumRetryCount 0` is set for every request in this mode; the write guard also rejects every second POST and every path except `EntityDefinitions`. PATCH/DELETE are unsupported by the request wrapper. The recovery branch returns before the normal Apply continuation, so it cannot post additional attributes or call PublishXml. Terminal states cannot authorize another write. Any partial/unexpected metadata takes precedence; exact metadata and Solution membership are required for VERIFIED_SUCCESS. Do not publish, delete, recreate, compensate, or change roles/privileges. Local tests use mocked transport only; **remote execution remains unauthorized**.

#### Sanitized Evidence Record (Template)

Keep any operational record outside the repository unless organizational policy approves a sanitized incident artifact. Use null/omitted values when an item was not returned; never infer evidence. The local mode's diagnostic is not an approval record.

| Record area | Allowlisted fields |
|---|---|
| Preflight | `attemptTimestampUtc`; `environmentName` (`VN LMV IT`); `environmentMatch` Boolean; `identityMatch` Boolean (expected ID/PAC/Az same user; no user identifier); `solutionUniqueName`; `solutionType` (`unmanaged`); `publisherUniqueName`; `publisherPrefix`; `targetTableAbsent` Boolean; `solutionComponentAbsent` Boolean; effective privilege results; `payloadSha256`. |
| Request/response | `method` (`POST`); relative `path` (`/api/data/v9.2/EntityDefinitions`); `httpStatus`; allowlisted sanitized Dataverse error code/message; valid request/correlation GUIDs only; selected safe challenge properties only; `tokenAudienceValid`, `tokenScopeValid`, `tokenExpiryValid` Booleans; `writesMayHaveOccurred` Boolean. |
| Reconciliation | `reconciliationTimestampUtc`; GET-only results for target table and metadata, exact expected attributes, keys, relationships, and project Solution root; `outcome` (`VERIFIED_SUCCESS`, `FAILED_AUTH`, `FAILED_AUTHZ`, `FAILED_VALIDATION`, `UNCERTAIN`, or `PARTIAL_STATE`); concise sanitized notes. |

Never include access/refresh tokens, Authorization or other full headers, JWT claims, user email, tenant ID, full organization URL, credentials, full response body, candidate data, or unfiltered exception text. The emitted diagnostic includes redacted verification booleans and the Position fingerprint; it does not prove external authorization or emit raw identity/token claims. The historical incident was not captured with these fields.

#### Position Payload Identity

The offline Position PlanOnly payload was serialized from `TablePayload` using `ConvertTo-Json -Depth 40 -Compress`, encoded as UTF-8 without a BOM, and hashed with SHA-256. Fingerprint: **`0f7372eeb66c0214ae08ed0dc74f82c981cc4cd73baa9156f16d6e1bd1f48e80`**. The synthetic provisioning test recalculates and asserts this value. It fingerprints the table-create payload (table plus primary-name attribute), not future requests, environment identity, or the entire Apply sequence. Recalculate after any payload/script change; a mismatch blocks use of the recorded approval until reviewed.

#### Exact GET-Only Reconciliation

After the single authorized POST—or any uncertain result—use only the existing verified Dataverse organization and the existing authenticated identity. Do not follow untrusted continuation URLs. Inspect:

1. `GET EntityDefinitions(LogicalName='os_sr_pos')` for exact logical/schema name, metadata ID, `OrganizationOwned`, display `Position`, plural `Positions`, `PrimaryIdAttribute`, and `PrimaryNameAttribute`.
2. `GET EntityDefinitions(LogicalName='os_sr_pos')/Attributes` and compare custom attributes with exactly one declared custom attribute: primary `os_sr_pos_ttl`, String/Text, length 200, `ApplicationRequired`, `IsPrimaryName=true`. Confirm the generated primary GUID attribute exists and is the PrimaryIdAttribute; ignore standard platform attributes only after classifying them as noncustom. Any other custom attribute means `PARTIAL_STATE`.
3. `GET EntityDefinitions(LogicalName='os_sr_pos')/Keys` and all three relationship collections (`ManyToOneRelationships`, `OneToManyRelationships`, `ManyToManyRelationships`); expect no custom keys or relationships. Any unexpected custom metadata means `PARTIAL_STATE`.
4. Query `solutioncomponents` read-only for the project Solution ID and the table MetadataId, component type Entity (`1`). Verify a Solution root component and `rootcomponentbehavior=0` (includes subcomponents), or the exact explicitly supported membership representation. No membership or conflicting membership blocks `VERIFIED_SUCCESS`.
5. Reconfirm the project Solution identity and retrieve the selected table metadata a second time if the first read is inconsistent. Reads do not authorize writes.

The table and names are durable creation-time metadata: there is no automatic rollback. Leave partial or unpublished metadata untouched pending a separate admin-reviewed recovery plan. Do not run `PublishXml` as part of this one-POST attempt.

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

## Phase 2D Adopted App Composition

[Configure-BsoRsModelDrivenApp.ps1](Configure-BsoRsModelDrivenApp.ps1) targets only the adopted `srapp` AppModule. No switches means **PlanOnly**: local payload preview with no authentication, PAC call, or network request. `-DryRun` verifies PAC/Az identity, AppModule/Solution/Site Map/table/form/view metadata, the Solution `AppModuleSiteMap` binding, live AddAppComponents OData metadata, and Solution-export form/view membership using GETs and a temporary export ZIP that is deleted in `finally`.

The maximum sequence is two independent requests: PATCH only `sitemapxml` on the existing Site Map, then POST AddAppComponents for the existing TA table, Main form, and public view. The Site Map is not re-added because the Solution export already binds unique name `srapp`. The script does not call PublishXml/PublishAllXml, change role/audit records, delete components, or read business rows. Each write is followed by independent GET read-back; no retry, transaction, or rollback is assumed. If a write is ambiguous or read-back fails, stop and reconcile.

Only a separately approved future Apply may use `-Apply`, the exact confirmation phrase, a nonempty authorization reference, and the process-scoped identity values below. **Do not execute Apply under Phase 2D-P.**

```powershell
& ./scripts/Configure-BsoRsModelDrivenApp.ps1
& ./scripts/Configure-BsoRsModelDrivenApp.ps1 -DryRun
```

DryRun requires `BSO_RS_ENVIRONMENT_NAME`, `BSO_RS_ORG_URL`, `BSO_RS_EXPECTED_ENVIRONMENT_ID`, and `BSO_RS_EXPECTED_ORG_ID` in the current process; never save their values in the repository. Runtime AddAppComponents acceptance on this unpublished app and whether Site Map PATCH creates the expected unpublished layer remain unverified. See the [Phase 2D runbook](../docs/MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md).

## Phase 2D Adopted App Composition (Prepared, Not Authorized)

[Configure-BsoRsModelDrivenApp.ps1](Configure-BsoRsModelDrivenApp.ps1) targets only the owner-adopted AppModule `srapp`. Running it with no switches is **PlanOnly**: it prints the planned operations and typed `AddAppComponents` payloads without authentication, PAC, or network calls. `-DryRun` performs PAC identity checks and GET-only verification of the AppModule, Solution, Site Map, TA table/form/view, AppModuleSiteMaps export binding, and live OData action/component metadata. It also exports the target Solution to a temporary ZIP and deletes it in `finally`.

The maximum sequence is two independent writes: PATCH only `sitemapxml` on the existing Site Map, then POST `AddAppComponents` for the existing table, Main form, and public view. The Site Map is omitted from that action because the target Solution export already contains `AppModuleSiteMap.SiteMapUniqueName=srapp`. There is no `$batch`, transaction, rollback, retry, delete, PublishXml, PublishAllXml, role, audit, or business-data operation. Each write has an independent read-back; an uncertain or partial result stops without compensating writes. The script requires `-Apply`, the exact confirmation phrase, a nonempty authorization reference, and process-scoped VN LMV IT identity variables. **Do not use Apply until a separate Phase 2D authorization exists.**

Run PlanOnly and GET-only DryRun:

```powershell
& ./scripts/Configure-BsoRsModelDrivenApp.ps1
& ./scripts/Configure-BsoRsModelDrivenApp.ps1 -DryRun
```

DryRun requires `BSO_RS_ENVIRONMENT_NAME`, `BSO_RS_ORG_URL`, `BSO_RS_EXPECTED_ENVIRONMENT_ID`, and `BSO_RS_EXPECTED_ORG_ID` in the current process. Do not persist their values in the repository. Runtime acceptance of the AddAppComponents action on this unpublished app and the Site Map PATCH's draft-layer behavior remain unverified; see the [Phase 2D Runbook](../docs/MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md).
