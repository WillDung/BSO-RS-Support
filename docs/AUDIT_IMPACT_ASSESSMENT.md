# Dataverse Audit Impact Assessment

**Status:** Read-only assessment, refreshed 17 November 2026 after Candidate Core 1.0.9 deployment. No environment, auditing, retention, or DLP settings were changed. This project assessment is not an organizational policy and does not establish additional approval authorities.

## NORMAL Create Candidate runtime and control classification

Candidate Core 1.0.9 adds no audit setting or audit-table metadata changes. The organization-level audit switch is off; live table flags for Candidate, Call Log and Candidate Status History are enabled. With organization auditing off, these table flags do not produce Dataverse audit entries. Per-column flags, log capacity, retention policy, authorized audit readers, DSR/legal-hold handling, and monitoring ownership are not established by this assessment. Candidate Name, Email, optional Phone, Position/Source/TA, operation correlation, owner, and generated Candidate Number are processed by the application; a CV URL is a sensitive downstream booking field. The new Candidate Number response is not written to diagnostic logs by the source.

The actual Candidate Core runtime gate checks an active exact-organization `os_sr_ncrcfg` value and the initiating user's effective `prvCreateos_sr_cand`, in addition to server-side required-field, Active-reference, ownership, correlation/idempotency and readback checks. It does not inspect organization auditing, retention, DLP, privacy approvals, or incident ownership. Those are not platform requirements of this API. Do not infer policy compliance from the owner’s Go Live decision; equally, do not treat an unverified project checklist as proof that a separate corporate approval is mandatory.

The owner authorized application Go Live for owner-entered real Candidate data on 17 November 2026. This is the app owner's business decision only. No applicable corporate policy in the available project evidence establishes environment-wide auditing, a specific retention period, a separate privacy sign-off, DLP confirmation, or named incident ownership as an activation gate. Those matters remain unverified and are not represented as satisfied or as a demonstrated blocker. The owner-authorized deployment does not change any shared audit or DLP setting. See [Current State](CURRENT_STATE.md).

## Verified Facts

- PAC `org who` again matched **VN LMV IT** on 17 November 2026.
- PAC `org list-settings --filter audit` reports `isauditenabled=false`, `auditretentionperiod=30`, `auditretentionperiodv2` unset, `isuseraccessauditenabled=false`, `isreadauditenabled=false`, `issendcuaauditlogtopurviewenabled=false`, and `auditsettings={"IsSqlAuditWriteDisabled":true}`. The 30-day value is current configuration only, not policy approval; the SQL audit flag's effect is unknown.
- Read-only Dataverse EntityDefinitions metadata confirms `IsAuditEnabled=true` on `os_sr_cand`, `os_sr_call`, and `os_sr_csh`. Environment auditing being off prevents these table flags from producing Dataverse audit entries.
- Organization metadata includes `auditsettings` value `IsSqlAuditWriteDisabled=true`; its relationship to Dataverse auditing is **UNKNOWN** pending authoritative interpretation.
- Read-only DLP inventory returned 12 tenant policies. A direct detail recheck of `LEGO Global Policy` confirms `ExceptEnvironments`, default `General`, and 95 Confidential / 1,676 General / 4 Blocked connectors, but returns no excluded-environment IDs or connector identities; the listed `OnlyEnvironments` policies expose no scope IDs either. Applicable policy and Dataverse connector treatment for VN LMV IT remain **UNKNOWN**.
- The fresh read-only unmanaged Solution export confirms the BSO-RS-Support solution, project tables, and Console resources are present. Per-column flags and table audit flags/dependencies in other solutions remain **UNKNOWN**; the export did not include audit history or business records.
- No audit table/history contents, Candidate rows, or other business records were accessed.
- The project records an owner-approved requirement to audit the three named tables, but no approved organizational real-Candidate privacy/data-processing policy or policy reference. Product requirements remain Candidate Name and Email required, Phone optional, and CV URL sensitive at booking; actual real-data use is not authorized by technical deployment.
- The production blocker ledger identifies the Privacy/DLP owner for the DLP/privacy decision and Service owner for monitoring/incident ownership. No names, runbook, alert owner, or incident assignment are evidenced.
- Log capacity allocation/consumption, existing table/column audit flags, prior audit-log existence/volume, and table-level auditing for other apps are **UNKNOWN**. The inspected PAC commands expose environment inventory, not capacity reports. Microsoft's Capacity page requires tenant admin, Power Platform admin, Dynamics 365 admin, or delegated permission.

## Impact Assessment

| Area | Assessment | Evidence class |
|---|---|---|
| Environment-wide behavior | Start Auditing is environment-level. It enables collection only where table and column auditing are configured; selecting a common-entity preset can affect many built-in tables and applications. This is not a technical prerequisite for the Candidate Core API. Do not choose that preset without an applicable policy and authorization for its shared impact. | Microsoft-documented behavior; current environment setting verified off. Required project table flags are on. |
| Existing apps/tables | Other solutions exist in the environment, but their table audit flags/dependencies were not enumerated. If environment auditing is enabled, any already-audited tables may begin generating logs. App-specific exposure is UNKNOWN. | Existing solutions are known; audit configuration is not. |
| Log storage | AuditBase uses Dataverse Log capacity. Growth depends on audited tables/columns, create/update/delete frequency, sharing events, and retention. Current allocation, usage, and remaining capacity are UNKNOWN. | Microsoft-documented storage category; environment metrics unavailable in current tools. |
| Performance | Auditing adds write-path work and log volume; exact impact for this environment/workload is UNKNOWN and must be load-tested/monitored. No performance measurement was performed. | Risk assessment, not measured fact. |
| Sensitive-data exposure | Audit values can retain before/after values for selected columns. Candidate PII, salary, CV URLs, email recipients/content, and resource addresses can therefore appear in logs if selected. Audit access is separate from table/column access. | Microsoft-documented behavior; project exposure is prospective. |
| Security role requirements | Microsoft documents System Administrator/System Customizer or equivalent for configuration; viewing Audit History/Audit Summary requires corresponding privileges. Exact assigned roles/readers are UNKNOWN. | Microsoft-documented; current role assignments not inspected. |
| User-access auditing | Separate environment setting; in Production, user-access/activity logs are sent to Purview where feature/licensing requirements are met. This may cover more than the project and needs policy/licensing review. Current toggle is off. | Current toggle verified; destination/licensing and policy UNKNOWN. |
| Retention change | Current 30 days is not approved. Microsoft documents that retention-change path matters: one setting applies to new logs, while the Security/Auditing configuration can affect existing logs. Historic log existence and policy scope are UNKNOWN. | Current setting verified; historical impact not examined. |
| Monitoring/ownership | Audit capacity alerting, operational review, incident owner, and approval owner were not identified in this bounded assessment. | UNKNOWN; not a verified runtime prerequisite. No monitoring or organization setting was changed. |
| Rollback | Turning auditing off stops future collection but does not reverse disclosure or restore deleted logs. Audit deletion is irreversible for the covered history; retention changes may trigger deletion depending on path/policy. | Microsoft-documented behavior. |
| `os_sr_csh` dependency | The application-owned Status History table is a purpose-built business record written atomically with Candidate status. It is not a Dataverse audit log and must remain available even if auditing is disabled. Dataverse auditing supplements it. | Confirmed project requirement. |

## Proposed Settings (Not Applied)

| Scope | Proposal |
|---|---|
| Environment Start Auditing | Not changed. Enable only if an applicable documented policy requires it and the shared-environment impact is authorized. |
| Retention | Current 30 days is observed configuration, not an approved policy. No retention change is part of this release. |
| User Access Auditing | Not changed; applicability and licensing were not established and it is not a Candidate Core runtime requirement. |
| Project table auditing | Required table flags for Candidate, Call Log and Status History are already enabled. |
| Sensitive columns | No column audit changes were made. See [Dataverse Audit Policy](DATAVERSE_AUDIT_POLICY.md) for the recorded evidence limitations. |

## Evidence boundary

The available evidence does not establish that the listed governance details are satisfied, nor that any is an independent activation prerequisite. The direct Dataverse Console path does not use a Power Automate or external connector. DLP applicability was not resolved, and no specific conflict was observed. Do not assert corporate-policy compliance or make shared-environment changes from this assessment. The exact runtime configuration, server authorization, and owner's app-level release decision are tracked separately in [Current State](CURRENT_STATE.md).

## Limitations

This assessment used organization configuration metadata only. It did not inspect audit entries, candidate/employee data, table-level audit metadata across the environment, capacity reports, security role assignments, or Purview configuration. Unknowns above must not be treated as negative findings.
