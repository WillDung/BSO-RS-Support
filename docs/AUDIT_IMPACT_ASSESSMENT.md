# Dataverse Audit Impact Assessment

**Status:** Read-only assessment, refreshed 17 November 2026 after Candidate Core 1.0.9 deployment. No environment, auditing, retention, or DLP settings were changed. Findings distinguish verified configuration from approvals and unknowns.

## NORMAL Create Candidate activation gate (technical release deployed disabled)

Candidate Core 1.0.9 adds no audit setting or audit-table metadata changes. The organization-level audit switch is off; live table flags for Candidate, Call Log and Candidate Status History are enabled. Per-column flags, log capacity, approved retention, authorized audit readers, DSR/legal-hold handling, and monitoring ownership are not established. Candidate Name, Email, optional Phone, Position/Source/TA, operation correlation, owner, and generated Candidate Number are subject to organizational privacy and audit policy; a CV URL is a sensitive downstream booking field. The new Candidate Number response is not written to diagnostic logs by the source.

Do not treat plug-in tracing or a successful package build as audit/privacy approval. Before enabling the NORMAL server gate, an authorized IT/Compliance decision-maker must approve the project table/column audit matrix, policy/retention and historical-log effects, audit-reader access, data minimization, operational monitoring/incident response, and applicable DLP controls. No value enabling `os_sr_ncrcfg` is included in source or artifact preparation.

The owner-authorized 1.0.9 disabled technical delta is now deployed and verified; its one active exact-org value is `enabled=false`. No audit/governance setting was changed and no Candidate action or business-data test was executed. Existing off/unknown observations below are reused, not another broad investigation. Audit/approved retention, applicable DLP, privacy/minimization and operational acceptance block **activation**, not the completed routine engineering. Exact target binding and technical change authorization are established; see [Current State](CURRENT_STATE.md).

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
| Environment-wide behavior | Start Auditing is environment-level. It enables collection only where table and column auditing are configured; selecting a common-entity preset can affect many built-in tables and applications. Do not choose that preset without a cross-environment/table scope review. | Microsoft-documented behavior; current environment setting verified off. Existing table flags UNKNOWN. |
| Existing apps/tables | Other solutions exist in the environment, but their table audit flags/dependencies were not enumerated. If environment auditing is enabled, any already-audited tables may begin generating logs. App-specific exposure is UNKNOWN. | Existing solutions are known; audit configuration is not. |
| Log storage | AuditBase uses Dataverse Log capacity. Growth depends on audited tables/columns, create/update/delete frequency, sharing events, and retention. Current allocation, usage, and remaining capacity are UNKNOWN. | Microsoft-documented storage category; environment metrics unavailable in current tools. |
| Performance | Auditing adds write-path work and log volume; exact impact for this environment/workload is UNKNOWN and must be load-tested/monitored. No performance measurement was performed. | Risk assessment, not measured fact. |
| Sensitive-data exposure | Audit values can retain before/after values for selected columns. Candidate PII, salary, CV URLs, email recipients/content, and resource addresses can therefore appear in logs if selected. Audit access is separate from table/column access. | Microsoft-documented behavior; project exposure is prospective. |
| Security role requirements | Microsoft documents System Administrator/System Customizer or equivalent for configuration; viewing Audit History/Audit Summary requires corresponding privileges. Exact assigned roles/readers are UNKNOWN. | Microsoft-documented; current role assignments not inspected. |
| User-access auditing | Separate environment setting; in Production, user-access/activity logs are sent to Purview where feature/licensing requirements are met. This may cover more than the project and needs policy/licensing review. Current toggle is off. | Current toggle verified; destination/licensing and policy UNKNOWN. |
| Retention change | Current 30 days is not approved. Microsoft documents that retention-change path matters: one setting applies to new logs, while the Security/Auditing configuration can affect existing logs. Historic log existence and policy scope are UNKNOWN. | Current setting verified; historical impact not examined. |
| Monitoring/ownership | Audit capacity alerting, operational review, incident owner, and approval owner are not identified. | UNKNOWN; no technical config change is supported without an assigned owner and approved policy. |
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

## Required organizational evidence before activation

1. IT/Compliance: provide approved audit policy/reference, retention period and historic-log effect, audit-reader, legal-hold/DSR, export and capacity evidence; approve impact of the organization-wide audit toggle on other applications.
2. Privacy/Data Protection: authorize real Candidate processing purpose and fields, minimization, access, retention/deletion and candidate-data use.
3. Power Platform DLP governance: identify the actual policy applying to the exact environment and the classification/treatment of the Dataverse connector (and any future connectors).
4. Service owner: name monitoring/incident responsibility and provide operational alert/escalation evidence.
5. Environment/change authority: after the above, authorize the exact organization-bound `os_sr_ncrcfg` activation. No audit, retention, DLP or gate setting is changed by this assessment.

## Limitations

This assessment used organization configuration metadata only. It did not inspect audit entries, candidate/employee data, table-level audit metadata across the environment, capacity reports, security role assignments, or Purview configuration. Unknowns above must not be treated as negative findings.
