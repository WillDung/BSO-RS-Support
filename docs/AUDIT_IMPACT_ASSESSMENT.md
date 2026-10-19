# Dataverse Audit Impact Assessment

**Status:** Read-only assessment, 19 October 2026. No environment or auditing settings were changed. Findings distinguish verified configuration from assumptions and unknowns.

## Verified Facts

- The connected environment is **VN LMV IT**, Production-class and explicitly selected for internal IT development. No environment switch occurred.
- Organization metadata reports `isauditenabled=false`, `auditretentionperiod=30`, and `isuseraccessauditenabled=false`. The 30-day value is current configuration only, not policy approval.
- Organization metadata includes `auditsettings` value `IsSqlAuditWriteDisabled=true`; its relationship to Dataverse auditing is **UNKNOWN** pending authoritative interpretation.
- The BSO-RS-Support Publisher and empty unmanaged Solution exist. A read-only Solution Component query returned no rows; the five tables in the project audit scope are not deployed.
- No audit table/history contents or business records were accessed.
- Log capacity allocation/consumption, existing table/column audit flags, prior audit-log existence/volume, and table-level auditing for other apps are **UNKNOWN**. The inspected PAC commands expose environment inventory, not capacity reports. Microsoft's Capacity page requires tenant admin, Power Platform admin, Dynamics 365 admin, or delegated permission.

## Impact Assessment

| Area | Assessment | Evidence class |
|---|---|---|
| Environment-wide behavior | Start Auditing is environment-level. It enables collection only where table and column auditing are configured; selecting a common-entity preset can affect many built-in tables and applications. Do not choose that preset without a cross-environment/table scope review. | Microsoft-documented behavior; current environment setting verified off. Existing table flags UNKNOWN. |
| Existing apps/tables | Other solutions exist in the environment, but their table audit flags/dependencies were not enumerated. If environment auditing is enabled, any already-audited tables may begin generating logs. App-specific exposure is UNKNOWN. | Existing solutions are known; audit configuration is not. |
| Log storage | AuditBase uses Dataverse Log capacity. Growth depends on audited tables/columns, create/update/delete frequency, sharing events, and retention. Current allocation, usage, and remaining capacity are UNKNOWN. | Microsoft-documented storage category; environment metrics unavailable in current tools. |
| Performance | Auditing adds write-path work and log volume; exact impact for this environment/workload is UNKNOWN and must be load-tested/monitored. No performance measurement was performed. | Risk assessment, not measured fact. |
| Sensitive-data exposure | Audit values can retain before/after values for selected columns. Candidate PII, salary, CV URLs, email recipients/content, and resource addresses can therefore appear in logs if selected. Audit access is separate from table/column access. | Microsoft-documented behavior; project exposure is prospective. |
| Security role requirements | Microsoft documents System Administrator/System Customizer or equivalent for configuration; viewing Audit History/Audit Summary requires corresponding privileges. Exact assigned roles/readers are UNKNOWN. | Microsoft-documented; current role assignments not inspected. |
| User-access auditing | Separate environment setting; in Production, user-access/activity logs are sent to Purview where feature/licensing requirements are met. This may cover more than the project and needs policy/licensing review. Current toggle is off. | Current toggle verified; destination/licensing and policy UNKNOWN. |
| Retention change | Current 30 days is not approved. Microsoft documents that retention-change path matters: one setting applies to new logs, while the Security/Auditing configuration can affect existing logs. Historic log existence and policy scope are UNKNOWN. | Current setting verified; historical impact not examined. |
| Monitoring/ownership | Audit capacity alerting, operational review, incident owner, and approval owner are not identified. | UNKNOWN. |
| Rollback | Turning auditing off stops future collection but does not reverse disclosure or restore deleted logs. Audit deletion is irreversible for the covered history; retention changes may trigger deletion depending on path/policy. | Microsoft-documented behavior. |
| `os_sr_csh` dependency | The application-owned Status History table is a purpose-built business record written atomically with Candidate status. It is not a Dataverse audit log and must remain available even if auditing is disabled. Dataverse auditing supplements it. | Confirmed project requirement. |

## Proposed Settings (Not Applied)

| Scope | Proposal |
|---|---|
| Environment Start Auditing | **PENDING IT/COMPLIANCE APPROVAL** |
| Retention | Use the approved organizational IT/Compliance policy; exact period and historic-log treatment are **UNRESOLVED**. Do not adopt 30 days by default. |
| User Access Auditing | **PENDING IT/COMPLIANCE APPROVAL** and license/Purview review. |
| Project table auditing | Enable only after policy approval, capacity review, per-table/column matrix approval, and change control. |
| Sensitive columns | Follow [Dataverse Audit Policy Proposal](DATAVERSE_AUDIT_POLICY.md); do not audit content merely because table audit is proposed. |

## Required Gates Before Activation

1. Receive written answers to the ten questions in [Dataverse Audit Policy Proposal](DATAVERSE_AUDIT_POLICY.md).
2. Obtain a capacity report from an authorized admin and confirm log allocation, consumption, growth forecast, and monitoring owner.
3. Read-only inventory all existing table audit flags and any common-entity preset/dependencies before enabling the environment switch.
4. Approve project table and column matrix, including whether sensitive PII/content values may enter audit logs.
5. Identify authorized audit readers and configure least-privilege privileges; confirm Purview and licensing for access logging if selected.
6. Confirm retention control path, historical-log effect, legal hold, DSR, export/preservation, and rollback procedure.
7. Record formal IT/Compliance and change-management approval. Only then prepare a separately approved implementation change.

## Limitations

This assessment used organization configuration metadata only. It did not inspect audit entries, candidate/employee data, table-level audit metadata across the environment, capacity reports, security role assignments, or Purview configuration. Unknowns above must not be treated as negative findings.
