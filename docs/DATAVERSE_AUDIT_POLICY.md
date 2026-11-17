# Dataverse Audit Policy Proposal

**Status:** Read-only assessment refreshed 17 November 2026. No auditing, retention, security, DLP, or environment setting was changed. IT/Compliance policy and approval are required before NORMAL Create activation.

## Verified Current Configuration

The connected environment was verified as **VN LMV IT**, Production-class and explicitly selected for internal IT development. The BSO-RS-Support solution and Candidate Core are deployed. Configuration and entity metadata were read only; no business records or audit entries were read.

| Setting | Verified value | Interpretation |
|---|---|---|
| Environment auditing (`isauditenabled`) | `false` (PAC read 17 November) | Dataverse auditing is currently off at environment level. |
| Configured audit retention (`auditretentionperiod`) | `30` days (PAC read 17 November) | Current technical configuration only; it is **not** an approved BSO-RS-Support retention decision. |
| Retention v2 (`auditretentionperiodv2`) | Unset (PAC read 17 November) | No approved policy or effective v2 duration is evidenced. |
| User-access/read auditing and Purview forwarding | All `false` (PAC read 17 November) | Environment-wide controls are off; whether required remains an IT/Compliance decision. |
| Audit settings JSON | `IsSqlAuditWriteDisabled: true` | Value observed; its effect on Dataverse audit functionality is UNKNOWN and requires Microsoft/platform-owner interpretation. |
| Log-capacity entitlement, allocation, and consumption | UNKNOWN | Not exposed by the read-only MCP query or PAC environment inventory used in this assessment. |
| Required project table audit flags | Candidate, Call Log, Candidate Status History all `IsAuditEnabled=true` (live metadata read 17 November) | Table metadata meets the approved project requirement; it produces no Dataverse audit entries while organization auditing is off. |
| Table/column audit flags across other existing components | UNKNOWN | Only the three required project tables were checked in this bounded re-read; do not infer impact to other apps. |
| Existing historical audit-log presence, volume, and stamped retention | UNKNOWN | Audit contents and audit-log tables were intentionally not queried. |
| Other application/table dependencies | UNKNOWN | Environment contains other organizational solutions; audit flags and dependencies for their tables were not inspected. |
| DLP policy inventory/applicability | 12 tenant policies listed; target applicability and Dataverse connector classification UNKNOWN | A read-only detail recheck of `LEGO Global Policy` reports `ExceptEnvironments`, default `General`, and 95 Confidential / 1,676 General / 4 Blocked connectors, but returns no excluded-environment IDs or connector identities. The listed `OnlyEnvironments` policies likewise expose no scope IDs in this tool. Do not infer which policy governs VN LMV IT or the Dataverse connector's classification. |

## Proposed Configuration (Not Applied)

| Scope | Proposed setting | Status |
|---|---|---|
| Environment | Start Auditing | **PENDING IT/COMPLIANCE APPROVAL** |
| Environment | Retention period | Follow the organization's approved IT/Compliance policy; value **UNRESOLVED**. Do not adopt the current 30-day value as policy. |
| Environment | User Access Auditing | **PENDING IT/COMPLIANCE APPROVAL**; decide whether this is required and confirm licensing/Purview destination. |
| Environment | Common-entity audit preset | Do not enable by default. Confirm the complete affected-table scope before any selection. |
| Candidate, Call Log, Candidate Status History | Table auditing | Required table flags are already `IsAuditEnabled=true`; organization-level auditing remains off. No environment-wide change was made. |
| Project reference tables | Table auditing | Proposed; live flags were not part of this bounded check. |
| Project tables | Column auditing | Use the matrix below as a proposal; live per-column settings were not checked. Minimize personal/resource identifiers and obtain approval for sensitive fields. |

Dataverse record auditing requires environment auditing plus table and selected-column settings. Enabling environment auditing is a global prerequisite; the table/column flags determine which record changes generate Dataverse audit rows. User-access/activity auditing is a separate environment-level concern. Do not confuse either with the application-owned `os_sr_csh` business history table.

## Reference-Table Audit Matrix (Proposed)

The listed fields are schema-proposal names. Audit selection is a proposal, not a configured state.

| Table | Table audit | Proposed column audit | Sensitive-data caveat |
|---|---|---|---|
| `os_sr_ta` | Enabled, pending policy | `os_sr_ta_nm`, `statecode`, `statuscode` | `os_sr_ta_eml` is contact data; audit only if IT/Compliance approves before/after email capture. |
| `os_sr_pos` | Enabled, pending policy | `os_sr_pos_ttl`, `statecode`, `statuscode` | Position-title changes support reference-data integrity. |
| `os_sr_csrc` | Enabled, pending policy | `os_sr_csrc_nm`, `statecode`, `statuscode` | Preserve source normalization and retirement history. |
| `os_sr_loc` | Enabled, pending policy | `os_sr_loc_nm`, `statecode`, `statuscode` | `os_sr_loc_rmeml` and `os_sr_loc_det` can expose operational identifiers/details; column auditing requires explicit approval and content review. |

## Business-Table Audit Matrix (Requirements and Proposals)

Candidate, Call Log, and Candidate Status History exist and their table audit flags were read as enabled on 17 November 2026. Other rows remain future/proposed. Column selections below are proposals, not verified live settings or approval to capture their values.

| Table | Table audit | Proposed column audit | Sensitive-data caveat |
|---|---|---|---|
| `os_sr_cand` | Enabled before candidate data is loaded | `os_sr_cand_stat`, ownership, and reference lookups; candidate identity/contact/CV fields only after approval | Name, email, phone, CV URL, and Candidate Number are sensitive. Candidate Number is a primary/alternate key and cannot be column-secured; restrict table/row access. |
| `os_sr_csh` | Enabled | Previous/new status, actor, changed time, reason, and correlation ID | This is application-owned transition history, not Dataverse auditing. Append-only operation design and key idempotency remain required even if Dataverse auditing is unavailable. Audit supplements it and may help detect edits/deletes. |
| `os_sr_irnd` | Enabled | Booking status, start/end, TA/location references, provider event ID, correlation | Candidate/TA associations and organizer identity may be sensitive. Approve field selection and access. |
| `os_sr_ires` | Enabled | Result, recorded-by, recorded-at | Feedback and salary are highly sensitive. Column auditing of `os_sr_ires_fb` and `os_sr_ires_sal` requires explicit approval because audit may retain before/after values. |
| `os_sr_edsp` | Enabled | Dispatch status, provider correlation, sent/attempt time, sanitized error | Do not column-audit To/CC, subject, or body snapshots by default; they contain sensitive communications. Verify whether create-event audit payloads include their values before enabling. Keep the protected immutable dispatch row as the full content snapshot; audit display may truncate large values. |

Any new table creation, column-level audit selections, key creation, or column-security profile remains subject to its own scope and approval. Audit matrix coverage is not permission to collect every value.

## IT/Compliance Approval Request

Please provide an approved decision or policy reference for each item. Do not infer defaults from the current environment setting.

| # | Decision required | IT/Compliance response |
|---|---|---|
| 1 | Required Dataverse audit retention period and governing policy/reference | **REQUIRED — UNRESOLVED** |
| 2 | Whether retention differs by data category/table, including HR/candidate data and email content | **REQUIRED — UNRESOLVED** |
| 3 | Whether a retention change applies only to future logs or also existing logs; approve the exact supported change path | **REQUIRED — UNRESOLVED** |
| 4 | Authorized users/roles for record Audit History and environment Audit Summary | **REQUIRED — UNRESOLVED** |
| 5 | Required audit export, Purview integration, archival, preservation, and evidence procedures | **REQUIRED — UNRESOLVED** |
| 6 | Legal-hold, investigation, and DSR/deletion requirements | **REQUIRED — UNRESOLVED** |
| 7 | Whether user-access auditing is required; scope, license prerequisites, and Purview destination | **REQUIRED — UNRESOLVED** |
| 8 | Audit-log capacity allocation, current usage, forecast owner, alert thresholds, and budget owner | **REQUIRED — UNRESOLVED** |
| 9 | Data-minimization rules for auditing PII, salary, CV links, email snapshots, and room/resource details | **REQUIRED — UNRESOLVED** |
| 10 | Named approval owner and required change-management/production approval procedure | **REQUIRED — UNRESOLVED** |

The project records no approved personal-data processing policy/reference for real Candidate data and no assigned incident/monitoring owner. The [Production Readiness Blocker Ledger](READINESS_BLOCKER_LEDGER.md) assigns these decisions to the Privacy/DLP owner and Service owner respectively; no individual or approval evidence is recorded. Do not infer either from the technical deployment authorization.

## Technical References

- [Manage Dataverse auditing](https://learn.microsoft.com/en-us/power-platform/admin/manage-dataverse-auditing): environment/table/column configuration, retention behavior, audit readers, and Purview-related user/activity logging.
- [Dataverse capacity-based storage details](https://learn.microsoft.com/en-us/power-platform/admin/capacity-storage): audit logs use Log storage; capacity views require tenant administrator, Power Platform administrator, or Dynamics 365 administrator access (or delegated permission).
